"""Install the isolated test APK explicitly, then use Flutter's existing-app driver."""
import os,re,subprocess,time
from urllib.parse import urlsplit,urlunsplit
from native_journey_evidence import require_native_journey, self_test

package='com.elevage.app.offlinevalidation'
device='emulator-5554'
adb=['adb','-s',device]
def run(args,timeout=180):
    return subprocess.run(args,check=True,text=True,capture_output=True,timeout=timeout).stdout

assert os.environ.get('GITHUB_ACTIONS')=='true', 'This helper is for the ephemeral CI emulator'
self_test()
assert run(adb+['shell','getprop','ro.build.version.sdk']).strip()=='24'
subprocess.run(['flutter','build','apk','--debug',
  '--target=integration_test/offline_foundations_test.dart','--target-platform=android-x64'],
  check=True,timeout=600)
installation=run(adb+['install','--no-streaming','-r','-t','build/app/outputs/flutter-apk/app-debug.apk'])
print(installation,flush=True)
assert re.search(r'^Success\s*$',installation,re.MULTILINE), 'Synthetic APK installation failed'
run(adb+['shell','am','force-stop',package])
run(adb+['shell','am','start','-n',package+'/com.elevage.app.MainActivity'])
deadline=time.monotonic()+90
uri=None
while time.monotonic()<deadline:
    process=subprocess.run(adb+['shell','pidof',package],capture_output=True,text=True,timeout=15).stdout.strip()
    if process:
        assert process.isdigit()
        logs=run(adb+['logcat','--pid='+process,'-d','-v','brief'])
        matches=re.findall(r'Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+)',logs)
        if matches:
            uri=matches[-1];break
    time.sleep(1)
assert uri is not None, 'The synthetic integration app did not expose its test VM service'
parts=urlsplit(uri)
host_port=run(adb+['forward','tcp:0','tcp:'+str(parts.port)]).strip()
assert host_port.isdigit()
endpoint=urlunsplit(('http','127.0.0.1:'+host_port,parts.path,'',''))
try:
    result=subprocess.run(['flutter','drive','--driver=test_driver/offline_foundations_driver.dart',
      '--use-existing-app='+endpoint,'--keep-app-running'],check=False,timeout=420)
    application_logs=run(adb+['logcat','--pid='+process,'-d','-v','brief'])
    require_native_journey(application_logs)
    if result.returncode:raise RuntimeError('Native Flutter driver exited with failure')
finally:
    run(adb+['shell','am','force-stop',package])
    run(adb+['forward','--remove','tcp:'+host_port])
