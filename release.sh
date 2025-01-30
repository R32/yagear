#!/bin/sh
DIR="yagear"
rm -f $DIR.zip
mkdir -p $DIR
cp -u yagear.lua yagear.toc $DIR
chmod -R 777 $DIR
zip -r $DIR.zip $DIR/
