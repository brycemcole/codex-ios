#!/usr/bin/env python3
from pathlib import Path
import subprocess
import shutil

root = Path(__file__).resolve().parent.parent
checkout = root / '.build/legacy-sdks'
commit = '0222fd5413cf4b9af096f37b4621afa2688572f7'
if not (checkout / '.git').is_dir():
    subprocess.run(['git', 'clone', '--filter=blob:none', '--no-checkout', 'https://github.com/theos/sdks.git', str(checkout)], check=True)
subprocess.run(['git', '-C', str(checkout), 'sparse-checkout', 'set', 'iPhoneOS9.3.sdk', 'iPhoneOS10.3.sdk'], check=True)
head = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
if head != commit:
    subprocess.run(['git', '-C', str(checkout), 'checkout', '--detach', commit], check=True)
for sdk in [checkout / 'iPhoneOS9.3.sdk', checkout / 'iPhoneOS10.3.sdk']:
    for path in sdk.rglob('*.tbd'):
        if path.is_symlink():
            continue
        text = path.read_text().replace(', i386', '').replace(', x86_64', '')
        path.write_text(text)
sdk = checkout / 'iPhoneOS10.3.sdk'
for name, symbols in [
    ('libobjc.A.tbd', '_objc_msgSend_stret, _objc_msgSendSuper2_stret'),
    ('libSystem.B.tbd', '__Unwind_SjLj_Register, __Unwind_SjLj_Unregister, __Unwind_SjLj_Resume'),
]:
    path = sdk / 'usr/lib' / name
    text = path.read_text()
    if symbols.split(',')[0] not in text:
        offset = text.index('[', text.index('symbols:')) + 1
        path.write_text(text[:offset] + ' ' + symbols + ',' + text[offset:])
sdk = checkout / 'iPhoneOS9.3.sdk'
shutil.copyfile(checkout / 'iPhoneOS10.3.sdk/usr/lib/system/liblaunch.tbd', sdk / 'usr/lib/system/liblaunch.tbd')
path = sdk / 'usr/lib/libSystem.B.tbd'
text = path.read_text()
symbols = ['_memcpy', '_memcmp', '_memset', '_memmove', '_bzero', '_memchr', '_memset_pattern16', '_strchr', '_strcmp', '_strncmp']
missing = [symbol for symbol in symbols if symbol + ',' not in text]
if missing:
    offset = text.index('[', text.index('symbols:')) + 1
    path.write_text(text[:offset] + ' ' + ', '.join(missing) + ',' + text[offset:])
