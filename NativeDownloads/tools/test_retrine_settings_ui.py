"""Native settings fixture with both of Spotify's page protocol names.

Uses an already booted iPhone simulator. No Spotify installation is simulated:
this verifies UIKit integration, language selection, menu rows and geometry.
"""
from pathlib import Path
import json
import os
import plistlib
import shutil
import subprocess
import time
from settings_fixture import SOURCES, fixture_includes

root=Path(__file__).resolve().parents[1]
out=Path(os.environ.get('PIXIE_TEST_BUILD_DIR', root/'build/retrine-settings-ui'))
app=out/'SpotifySettingsPreview.app'
app.mkdir(parents=True,exist_ok=True)
def run(*args,check=True):
 p=subprocess.run([str(x) for x in args],cwd=root,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=45)
 if check and p.returncode: raise RuntimeError(p.stdout)
 return p.stdout.strip()
devices=json.loads(run('xcrun','simctl','list','devices','--json'))['devices']
booted=[d for ds in devices.values() for d in ds if d['state']=='Booted' and d.get('isAvailable') and 'iPhone' in d['name']]
assert booted,'Boot an iPhone simulator first'
udid=os.environ.get('SIMULATOR_UDID') or booted[0]['udid']
sdk=run('xcrun','--sdk','iphonesimulator','--show-sdk-path')
objects=[]
includes=fixture_includes(out)
for src in [*SOURCES, root.parent/'tweak/Sources/Core/SGLocalize.m']:
 obj=out/(Path(src).stem+'.o');objects.append(obj)
 run('xcrun','clang','-c','-target','arm64-apple-ios26.0-simulator','-isysroot',sdk,'-fobjc-arc','-std=gnu11',*includes,'-DSAP_UI_FIXTURE',src,'-o',obj)
run('xcrun','swiftc','-swift-version','5','-parse-as-library','-target','arm64-apple-ios26.0-simulator','-sdk',sdk,'-import-objc-header','tests/SettingsFixtureBridge.h','tests/SettingsFixture.swift',*objects,'-Xlinker','-export_dynamic','-framework','UIKit','-framework','SwiftUI','-o',app/'SpotifySettingsPreview')
bundle='local.spotify.settingspreview.v4'
info={'CFBundleIdentifier':bundle,'CFBundleExecutable':'SpotifySettingsPreview','CFBundleName':'Settings Preview','CFBundleVersion':'24','CFBundleShortVersionString':'24','CFBundlePackageType':'APPL','CFBundleLocalizations':['ru','en','ko'],'CFBundleDevelopmentRegion':'en','LSRequiresIPhoneOS':True,'UIDeviceFamily':[1],'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'SAPFixtureSceneDelegate'}]}},'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait']}
(app/'Info.plist').write_bytes(plistlib.dumps(info))
shutil.copytree(root.parent/'tweak/layout/Library/Application Support/Retrine.bundle',app/'Retrine.bundle',dirs_exist_ok=True)
run('codesign','--force','--sign','-','--timestamp=none',app)
run('xcrun','simctl','install',udid,app)
for language in ['ko','en','ru']:
 run('xcrun','simctl','terminate',udid,bundle,check=False)
 container=Path(run('xcrun','simctl','get_app_container',udid,bundle,'data'))
 result=container/'Documents/result.log';result.unlink(missing_ok=True)
 print(run('xcrun','simctl','launch',udid,bundle,'-AppleLanguages','('+language+')'),flush=True)
 deadline=time.monotonic()+20
 while time.monotonic()<deadline:
  text=result.read_text() if result.exists() else ''
  if 'FAIL:' in text: raise RuntimeError(text)
  if 'PASS: entry spacing, mini-player clearance, navigation and native pages rendered' in text:break
  time.sleep(.3)
 else:raise RuntimeError('Fixture did not complete: '+text)
 assert 'PASS: legacy and module-qualified native page protocols;' in text
 target=out/language;target.mkdir(exist_ok=True)
 for file in (container/'Documents').iterdir():
  if file.suffix in ['.log','.png']:shutil.copy2(file,target/file.name)
 print(language+': '+text,flush=True)
print('PASS: KO/EN and RU fallback settings UI; real Retrine localization; protocols; no WAV; switch; navigation; mini-player clearance')
