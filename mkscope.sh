#!/bin/sh
rm -rf cscope.files cscope.out
#rm -rf cscope.files cscope.files
find ./ -name '*.[cCsShH]' > cscope.files
cscope -i cscope.files
