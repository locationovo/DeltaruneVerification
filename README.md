# DeltaruneVerification
## 编译
```bash
clang -arch arm64 \
  -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
  -mios-version-min=12.0 \
  -dynamiclib \
  -o libDeltaruneVerification.dylib \
  DeltaruneVerification.m \
  -framework Foundation -framework UIKit -framework WebKit \
  -fobjc-arc
```
## 注入
```bash
unzip target.ipa -d extracted
insert_dylib @executable_path/libDeltaruneVerification.dylib \
  extracted/Payload/DELTARUNE.app/DELTARUNE --all-yes
cp libDeltaruneVerification.dylib extracted/Payload/*.app/
cp verification_failed.png extracted/Payload/*.app/
codesign -f -s "证书名称" extracted/Payload/*.app/libDeltaruneVerification.dylib
codesign -f -s "证书名称" --entitlements entitlements.plist extracted/Payload/*.app
cd extracted && zip -qr ../target_verified.ipa Payload/
```
```bash
ldid -S libDeltaruneVerification.dylib
injectipa DELTARUNE.ipa libDeltaruneVerification.dylib
```
