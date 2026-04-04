```
xcodebuild -project ClaudeDesktop.xcodeproj -scheme ClaudeDesktop -configuration Release \
  -derivedDataPath ./build/DerivedData CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO build
./scripts/create-dmg.sh \
  "./build/DerivedData/Build/Products/Release/Claude Desktop.app" \
  ./build
```