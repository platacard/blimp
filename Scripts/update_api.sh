#!/bin/sh

TARGET=$1

curl -o openapi.zip https://developer.apple.com/sample-code/app-store-connect/app-store-connect-openapi-specification.zip
unzipped_file=$(unzip -Z1 openapi.zip | head -n 1)
unzip -p openapi.zip "$unzipped_file" > Sources/API/openapi.json

TARGET=$1

echo "Generating ${TARGET}"

swift run swift-openapi-generator generate Sources/API/${TARGET}/openapi.json \
--config Sources/API/${TARGET}/openapi-generator-config.yaml \
--output-directory Sources/API/${TARGET}/Generated

echo "Done!"
