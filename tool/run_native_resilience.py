"""Four launches of one isolated package; intentional crashes must have exact witnesses.

An unavailable real server is suspended only by its own Popen PID. No customer
package, emulator global clock/network, deployment URL or external DB is used.
"""
import base64
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
from urllib.parse import urlsplit,urlunsplit
from run_real_business import ROOT,PROOF,PRIVATE,PACKAGE,ADB,run,prepare_emulator_clock,restore_emulator_clock

BASELINE=ROOT/'build'/'native-baseline-mobile'
BASELINE_SHA='43ce0ee484c0af08d9de59e1bd38b9e1bca71243'

def application_logs(pid):
    return run(ADB+['logcat','--pid='+pid,'-d','-v','brief'])

def no_failure(log):
    assert not re.search(r'TestFailure|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK|Test timed out|Some tests failed|Unhandled Exception',log,re.I)

def wait_marker(pid,marker,timeout=120):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        log=application_logs(pid);no_failure(log)
        if marker in log:return log
        time.sleep(0.5)
    raise AssertionError('Missing native checkpoint: '+marker)

def launch():
    run(ADB+['shell','am','force-stop',PACKAGE])
    run(ADB+['shell','am','start','-n',PACKAGE+'/com.elevage.app.MainActivity'])
    deadline=time.monotonic()+90
    while time.monotonic()<deadline:
        pid=subprocess.run(ADB+['shell','pidof',PACKAGE],capture_output=True,text=True,timeout=15).stdout.strip()
        if pid:
            assert pid.isdigit()
            matches=re.findall(r'Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+)',application_logs(pid))
            if matches:
                parts=urlsplit(matches[-1]);port=run(ADB+['forward','tcp:0','tcp:'+str(parts.port)]).strip()
                assert port.isdigit()
                return pid,port,urlunsplit(('http','127.0.0.1:'+port,parts.path,'',''))
        time.sleep(0.5)
    raise AssertionError('Own test process has no VM service')

def stop(port):
    run(ADB+['shell','am','force-stop',PACKAGE]);run(ADB+['forward','--remove','tcp:'+port])

def drive(endpoint):
    subprocess.run(['flutter','drive','--driver=test_driver/native_resilience_driver.dart',
      '--use-existing-app='+endpoint,'--keep-app-running'],cwd=ROOT,check=True,timeout=420)

def signer(apk):
    candidates=sorted((Path(os.environ['ANDROID_HOME'])/'build-tools').glob('*/apksigner'))
    assert candidates,'Android SDK signer verifier missing'
    output=run([str(candidates[-1]),'verify','--print-certs',str(apk)])
    # Build-tools report either SDK-range Signer entries or scheme-specific V2/V3 Signer entries.
    digests={value.lower() for value in re.findall(
      r'^(?:Signer[^\n]*|V[1-4](?:\.[0-9]+)? Signer: )certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$',output,re.MULTILINE)}
    if len(digests)!=1:
        public_lines=[line for line in output.splitlines() if 'certificate SHA-256 digest:' in line]
        print('APK_PUBLIC_SIGNER_DIAGNOSTIC '+json.dumps(public_lines),flush=True)
    assert len(digests)==1,'One verified signing certificate SHA-256 required'
    return next(iter(digests))

def installed_version():
    output=run(ADB+['shell','dumpsys','package',PACKAGE])
    matches=re.findall(r'versionCode=(\d+)',output);assert len(matches)>=1
    return int(matches[0])

def main():
    assert os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('NATIVE_RESILIENCE')=='1'
    assert run(ADB+['shell','getprop','ro.build.version.sdk']).strip()=='24'
    run(ADB+['root']);run(ADB+['wait-for-device'],timeout=30)
    assert run(ADB+['shell','id','-u']).strip()=='0','Disposable emulator root required for packet interruption'
    packet_rule=['OUTPUT','-d','10.0.2.2/32','-p','tcp','--dport','9444','-j','DROP']
    def firewall(action):return run(ADB+['shell','iptables','-w',action,*packet_rule],timeout=30)
    assert subprocess.run(ADB+['shell','iptables','-w','-C',*packet_rule],capture_output=True,timeout=30).returncode==1
    assert not (PRIVATE/'ready').exists(),'Fresh CI fixture required'
    assert subprocess.check_output(['git','-C',str(BASELINE),'rev-parse','HEAD'],text=True).strip()==BASELINE_SHA
    assert not subprocess.check_output(['git','-C',str(BASELINE),'diff','--name-only'],text=True).strip()
    # Shared test instrumentation is untracked in the old checkout. Its production
    # sources, lockfile, native key adapter and SQLite schema remain the real 2H code.
    for relative in ['integration_test/native_resilience_test.dart','integration_test/grant_diagnostic_client.dart']:
        target=BASELINE/relative
        assert not target.exists(),'Never overwrite baseline source files'
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(ROOT/relative,target)
    subprocess.run(['flutter','pub','get','--enforce-lockfile'],cwd=BASELINE,check=True,timeout=180)
    assert not subprocess.check_output(['git','-C',str(BASELINE),'diff','--name-only'],text=True).strip()
    PROOF.mkdir(parents=True,exist_ok=True)
    with (PROOF/'server.log').open('w',encoding='utf-8') as server_log:
        server=subprocess.Popen([sys.executable,'tool/native_business_server.py'],cwd=ROOT,
          stdout=server_log,stderr=subprocess.STDOUT)
        current_port=None
        network_blocked=False
        previous_auto_time=None
        try:
            deadline=time.monotonic()+90
            while not (PRIVATE/'ready').exists():
                assert server.poll() is None,'Fixture server startup failed'
                assert time.monotonic()<deadline,'Fixture server startup timeout'
                time.sleep(1)
            ca=base64.b64encode((PRIVATE/'ca.pem').read_bytes()).decode()
            def build(version):
                source=BASELINE if version==101 else ROOT
                subprocess.run(['flutter','build','apk','--debug','--target=integration_test/native_resilience_test.dart',
                  '--target-platform=android-x64','--build-number='+str(version),'--dart-define=NATIVE_TEST_CA='+ca],
                  cwd=source,check=True,timeout=600)
                if version==101:
                    assert not subprocess.check_output(['git','-C',str(BASELINE),'diff','--name-only'],text=True).strip()
                return source/'build'/'app'/'outputs'/'flutter-apk'/'app-debug.apk'
            first=build(101);initial_signer=signer(first)
            assert re.search(r'^Success\s*$',run(ADB+['install','--no-streaming','-r','-t',str(first)]),re.MULTILINE)
            assert installed_version()==101
            previous_auto_time=prepare_emulator_clock()
            pid,current_port,endpoint=launch()
            log=wait_marker(pid,'REAL_WRITE_CRASH_READY transaction_open=true')
            (PROOF/'write-crash-before-stop.log').write_text(log,encoding='utf-8')
            stop(current_port);current_port=None
            pid,current_port,endpoint=launch();drive(endpoint)
            log=wait_marker(pid,'REAL_UPDATE_PENDING_READY pending=2 write_rollback=true')
            (PROOF/'write-crash-recovered.log').write_text(log,encoding='utf-8')
            stop(current_port);current_port=None
            updated=build(102);assert signer(updated)==initial_signer,'APK update changed signer'
            assert re.search(r'^Success\s*$',run(ADB+['install','--no-streaming','-r','-t',str(updated)]),re.MULTILINE)
            assert installed_version()==102
            (PROOF/'apk-update.json').write_text(json.dumps({'from_version':101,'to_version':102,
              'from_source':BASELINE_SHA,'to_source':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
              'same_signer_sha256':initial_signer,'install_replace':True,'uninstalled':False},indent=2)+'\n')
            pid,current_port,endpoint=launch()
            wait_marker(pid,'REAL_BACKEND_DOWN_READY pending=2')
            os.kill(server.pid,signal.SIGSTOP)
            log=wait_marker(pid,'REAL_BACKEND_UNAVAILABLE_RETAINED pending=2',timeout=60)
            os.kill(server.pid,signal.SIGCONT)
            wait_marker(pid,'REAL_SYNC_CRASH_READY pending=2')
            deadline=time.monotonic()+60
            while 'REAL_SYNC_CRASH_SERVER_PERSISTED originals=2' not in (PROOF/'server.log').read_text(encoding='utf-8'):
                no_failure(application_logs(pid))
                assert time.monotonic()<deadline,'Server never persisted both original UUIDs'
                time.sleep(0.5)
            firewall('-I');network_blocked=True
            wait_marker(pid,'REAL_MID_SYNC_PACKET_INTERRUPTION_CONFIRMED originals=2',timeout=20)
            (PROOF/'sync-crash-before-stop.log').write_text(application_logs(pid),encoding='utf-8')
            stop(current_port);current_port=None
            firewall('-D');network_blocked=False
            (PROOF/'mid-sync-network-interruption.json').write_text(json.dumps({'destination':'10.0.2.2:9444',
              'committed_originals':2,'client_request_in_flight':True,'independent_probe_timeout':True,
              'own_process_stopped_after_packet_cut':True,'exact_rule_removed':True,'production':False},indent=2)+'\n')
            pid,current_port,endpoint=launch();drive(endpoint)
            log=wait_marker(pid,'REAL_NATIVE_RESILIENCE_COMPLETE originals=2 effects=2 crash_write=true update=true crash_sync=true')
            (PROOF/'resilience-complete.log').write_text(log,encoding='utf-8')
            assert (PROOF/'server-resilience-verification.json').is_file()
            print('REAL_NATIVE_RESILIENCE_GATE_PASSED',flush=True)
        finally:
            try:
                if network_blocked:firewall('-D')
                if current_port:stop(current_port)
            finally:
                try:
                    if previous_auto_time is not None:restore_emulator_clock(previous_auto_time)
                finally:
                    if server.poll() is None:
                        os.kill(server.pid,signal.SIGCONT)
                        server.terminate()
                        try:server.wait(timeout=15)
                        except subprocess.TimeoutExpired:server.kill();server.wait(timeout=10)

if __name__=='__main__':main()
