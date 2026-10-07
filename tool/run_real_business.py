"""Own API24 test package -> real HTTPS Django/PostgreSQL -> checked evidence."""
import base64
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
            result=subprocess.run(['flutter','drive','--driver=test_driver/real_business_driver.dart',
              '--use-existing-app='+endpoint,'--keep-app-running'],cwd=ROOT,check=False,timeout=420)
            application=run(ADB+['logcat','--pid='+process,'-d','-v','brief'])
            # Own test process only; no secret bodies or authentication tokens are printed.
            (PROOF/'android.log').write_text(application,encoding='utf-8')
            require_completed(application)
            assert result.returncode==0,'Real native driver failed'
            assert (PROOF/'server-business-verification.json').is_file(),'No server-side business evidence'
            print('REAL_NATIVE_BUSINESS_GATE_PASSED',flush=True)
        finally:
            run(ADB+['shell','am','force-stop',PACKAGE])
            if port:run(ADB+['forward','--remove','tcp:'+port])
            server.terminate()
            try:server.wait(timeout=15)
            except subprocess.TimeoutExpired:server.kill();server.wait(timeout=10)

if __name__=='__main__':main()
