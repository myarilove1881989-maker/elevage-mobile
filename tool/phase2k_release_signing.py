"""Disposable CI Android 15 signing/update mechanics; never a distribution APK."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
PROOF=ROOT/'build'/'phase2k-signing-proof'
ADB=['adb','-s','emulator-5554']
assert os.environ.get('GITHUB_ACTIONS')=='true'
assert Path(os.environ['RUNNER_TEMP']).resolve() not in ROOT.resolve().parents
PROOF.mkdir(parents=True,exist_ok=True)

def run(args,env=None,check=True):
    result=subprocess.run(args,cwd=ROOT,env=env,text=True,capture_output=True)
    if check and result.returncode:
        # Commands contain only synthetic test inputs; private keys never printed.
        print(result.stdout[-12000:]);print(result.stderr[-12000:])
        raise RuntimeError('CI test command failed: '+args[0])
    return result

def sdk_tool(name):
    candidates=sorted((Path(os.environ['ANDROID_HOME'])/'build-tools').glob('*/'+name))
    assert candidates,name
    return str(candidates[-1])

def build(env,number=103,check=True):
    return run(['flutter','build','apk','--release','--build-number='+str(number),
        '--target-platform','android-arm64,android-x64',
        '--dart-define=API_URL=https://phase2k.synthetic.invalid/api'],env,check)

env={k:v for k,v in os.environ.items() if not k.startswith('ELEVAGE_')}
key=Path(os.environ['RUNNER_TEMP'])/'phase2k-TEST-ONLY.jks'
assert not key.resolve().is_relative_to(ROOT.resolve())
run(['keytool','-genkeypair','-keystore',str(key),'-storetype','PKCS12','-alias','phase2k-test-only',
    '-storepass','synthetic-test-only','-keypass','synthetic-test-only','-keyalg','RSA','-keysize','3072',
    '-validity','2','-dname','CN=PHASE 2K TEST ONLY DO NOT DISTRIBUTE'])
refused={}
for case,values,expected in (
    ('missing',{},'Release signing requires the four ELEVAGE signing environment variables.'),
    ('invalid_password',{'ELEVAGE_KEYSTORE_PATH':str(key),'ELEVAGE_KEYSTORE_PASSWORD':'wrong-test-password',
        'ELEVAGE_KEY_ALIAS':'phase2k-test-only','ELEVAGE_KEY_PASSWORD':'synthetic-test-only'},
        'Release signing credentials are invalid or the certificate has expired.'),
    ('invalid_alias',{'ELEVAGE_KEYSTORE_PATH':str(key),'ELEVAGE_KEYSTORE_PASSWORD':'synthetic-test-only',
        'ELEVAGE_KEY_ALIAS':'missing-test-alias','ELEVAGE_KEY_PASSWORD':'synthetic-test-only'},
        'Release signing credentials are invalid or the certificate has expired.'),
):
    result=build(dict(env,**values),check=False)
    assert result.returncode!=0 and expected in result.stdout+result.stderr,case
    refused[case]=True
valid=dict(env,ELEVAGE_KEYSTORE_PATH=str(key),ELEVAGE_KEYSTORE_PASSWORD='synthetic-test-only',
    ELEVAGE_KEY_ALIAS='phase2k-test-only',ELEVAGE_KEY_PASSWORD='synthetic-test-only')
assert run(ADB+['shell','getprop','ro.build.version.sdk']).stdout.strip()=='35'
run(ADB+['root']);run(ADB+['wait-for-device'])
assert run(ADB+['shell','id','-u']).stdout.strip()=='0'
proof={'test_certificate_only':True,'api_url':'https://phase2k.synthetic.invalid/api','sdk':35,
    'release_refusals':refused,'declarations_tested':False,'private_file_update_mechanics_only':True,'builds':[]}
previous=None
for number in (103,104):
    build(valid,number)
    apk=ROOT/'build/app/outputs/flutter-apk/app-release.apk'
    cert=run([sdk_tool('apksigner'),'verify','--verbose','--print-certs',str(apk)]).stdout
    fingerprints=set(re.findall(r'certificate SHA-256 digest: ([0-9a-fA-F]{64})',cert))
    assert len(fingerprints)==1
    fingerprint=next(iter(fingerprints)).lower()
    if previous:assert previous==fingerprint
    previous=fingerprint
    badging=run([sdk_tool('aapt'),'dump','badging',str(apk)]).stdout
    assert "package: name='com.elevage.app'" in badging
    assert f"versionCode='{number}'" in badging and "versionName='1.0.0'" in badging
    assert "sdkVersion:'24'" in badging
    assert 'application-debuggable' not in badging
    assert "'arm64-v8a'" in badging and "'x86_64'" in badging
    target=int(re.search(r"targetSdkVersion:'(\d+)'",badging).group(1))
    assert target>=35
    run(ADB+['install','--no-streaming','-r',str(apk)])
    run(ADB+['shell','am','start','-n','com.elevage.app/com.elevage.app.MainActivity'])
    sentinel='/data/user/0/com.elevage.app/files/phase2k-synthetic-update-sentinel'
    if number==103:
        run(ADB+['shell','mkdir','-p','/data/user/0/com.elevage.app/files'])
        run(ADB+['shell','sh','-c',"'printf phase2k-synthetic-preserved > "+sentinel+"'"])
    assert run(ADB+['shell','cat',sentinel]).stdout=='phase2k-synthetic-preserved'
    proof['builds'].append({'version_code':number,'version_name':'1.0.0','package':'com.elevage.app',
        'minimum_sdk':24,'target_sdk':target,'debuggable':False,
        'abis':['arm64-v8a','x86_64'],'certificate_sha256':fingerprint,
        'apk_sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'private_sentinel_preserved':True})
(PROOF/'signing-and-update.json').write_text(json.dumps(proof,indent=2)+'\n')
print('PHASE2K_TEST_CERT_RELEASE_UPDATE_PASSED')
