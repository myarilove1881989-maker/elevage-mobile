"""Own API24 test package -> real HTTPS Django/PostgreSQL -> checked evidence."""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.parse import urlsplit,urlunsplit

ROOT=Path(__file__).resolve().parent.parent
PROOF=ROOT/'build'/'native-business-proof'
PRIVATE=ROOT/'build'/'native-business-private'
PACKAGE='com.elevage.app.offlinevalidation'
ADB=['adb','-s','emulator-5554']

def run(args,timeout=180):
    return subprocess.run(args,check=True,capture_output=True,text=True,timeout=timeout).stdout

def require_completed(log):
    assert 'REAL_NATIVE_BUSINESS_COMPLETE originals=7 jean=6 paul=1 server_verified=true' in log
    assert not re.search(r'(TestFailure|Unhandled Exception|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK|test timed out|\[E\]|FAILURE|Some tests failed)',log,re.I)

def main():
    assert os.environ.get('GITHUB_ACTIONS')=='true'
    assert run(ADB+['shell','getprop','ro.build.version.sdk']).strip()=='24'
    # Disposable CI emulator only; one synthetic destination, no global flush.
    run(ADB+['root']);run(ADB+['wait-for-device'],timeout=30)
    assert run(ADB+['shell','id','-u']).strip()=='0','Isolated emulator root required for packet interruption'
    rule=['OUTPUT','-d','10.0.2.2/32','-p','tcp','--dport','9443','-j','DROP']
    def firewall(action):return run(ADB+['shell','iptables','-w',action,*rule],timeout=30)
    existing=subprocess.run(ADB+['shell','iptables','-w','-C',*rule],capture_output=True,text=True,timeout=30)
    assert existing.returncode==1,'Fresh emulator packet rules required'
    PROOF.mkdir(parents=True,exist_ok=True)
    # Guard verifies both completion and failure absence, never nominal driver exit alone.
    marker='REAL_NATIVE_BUSINESS_COMPLETE originals=7 jean=6 paul=1 server_verified=true'
    require_completed(marker)
    for bad in [marker+'\nTestFailure', 'Incomplete journey']:
        try:require_completed(bad)
        except AssertionError:pass
        else:raise AssertionError('Evidence guard accepted incomplete/failing test')
    with (PROOF/'server.log').open('w',encoding='utf-8') as server_log:
        server=subprocess.Popen([sys.executable,'tool/native_business_server.py'],cwd=ROOT,
          stdout=server_log,stderr=subprocess.STDOUT)
        port=None;process=None
        blocked=False;driver=None
        try:
            deadline=time.monotonic()+90
            while not (PRIVATE/'ready').exists():
                assert server.poll() is None,'Real test server failed before ready; inspect server.log'
                assert time.monotonic()<deadline,'Real test server startup timed out'
                time.sleep(1)
            public_ca=base64.b64encode((PRIVATE/'ca.pem').read_bytes()).decode()
            subprocess.run(['flutter','build','apk','--debug','--target=integration_test/real_business_test.dart',
              '--target-platform=android-x64','--dart-define=NATIVE_TEST_CA='+public_ca],cwd=ROOT,check=True,timeout=600)
            installed=run(ADB+['install','--no-streaming','-r','-t','build/app/outputs/flutter-apk/app-debug.apk'])
            assert re.search(r'^Success\s*$',installed,re.MULTILINE)
            run(ADB+['shell','am','force-stop',PACKAGE])
            run(ADB+['shell','am','start','-n',PACKAGE+'/com.elevage.app.MainActivity'])
            deadline=time.monotonic()+90
            endpoint=None
            while time.monotonic()<deadline:
                process=subprocess.run(ADB+['shell','pidof',PACKAGE],capture_output=True,text=True,timeout=15).stdout.strip()
                if process:
                    assert process.isdigit()
                    log=run(ADB+['logcat','--pid='+process,'-d','-v','brief'])
                    match=re.findall(r'Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+)',log)
                    if match:
                        parts=urlsplit(match[-1]);port=run(ADB+['forward','tcp:0','tcp:'+str(parts.port)]).strip()
                        assert port.isdigit()
                        endpoint=urlunsplit(('http','127.0.0.1:'+port,parts.path,'',''));break
                time.sleep(1)
            assert endpoint,'Real test APK has no VM service'
            driver=subprocess.Popen(['flutter','drive','--driver=test_driver/real_business_driver.dart',
              '--use-existing-app='+endpoint,'--keep-app-running'],cwd=ROOT)
            deadline=time.monotonic()+420
            disconnected=False;restored=False
            while driver.poll() is None:
                assert time.monotonic()<deadline,'Native business driver timeout'
                log=run(ADB+['logcat','--pid='+process,'-d','-v','brief'])
                if not disconnected and 'REAL_NETWORK_DISCONNECT_READY' in log:
                    firewall('-I');blocked=True;disconnected=True
                if blocked and 'REAL_NETWORK_RESTORE_READY' in log:
                    assert 'REAL_NETWORK_DISCONNECTED_CONFIRMED' in log
                    firewall('-D');blocked=False;restored=True
                time.sleep(0.25)
            application=run(ADB+['logcat','--pid='+process,'-d','-v','brief'])
            # Own test process only; no secret bodies or authentication tokens are printed.
            (PROOF/'android.log').write_text(application,encoding='utf-8')
            require_completed(application)
            assert driver.returncode==0,'Real native driver failed'
            assert disconnected and restored and 'REAL_NETWORK_RESTORED_CONFIRMED' in application
            (PROOF/'network-interruption.json').write_text(json.dumps({'ephemeral_emulator':True,
              'destination':'10.0.2.2:9443','packets_dropped':True,'request_timeout_verified':True,
              'restored_request_status':401,'rule_removed':True,'production':False},indent=2)+'\n')
            for evidence in ['server-business-verification.json','server-full-journey-verification.json',
              'server-expired-grants-verification.json','server-recovery-verification.json']:
                assert (PROOF/evidence).is_file(),'Missing server-side evidence: '+evidence
            print('REAL_NATIVE_BUSINESS_GATE_PASSED',flush=True)
        finally:
            try:
                if blocked:firewall('-D')
                if driver is not None and driver.poll() is None:
                    driver.terminate()
                    try:driver.wait(timeout=15)
                    except subprocess.TimeoutExpired:driver.kill();driver.wait(timeout=10)
                run(ADB+['shell','am','force-stop',PACKAGE])
                if port:run(ADB+['forward','--remove','tcp:'+port])
            finally:
                server.terminate()
                try:server.wait(timeout=15)
                except subprocess.TimeoutExpired:server.kill();server.wait(timeout=10)

if __name__=='__main__':main()
