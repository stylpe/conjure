#!/bin/bash

set -o errexit
set -o nounset

export BIN_DIR=${BIN_DIR:-${HOME}/.cabal/bin}

# wget -c http://savilerow.cs.st-andrews.ac.uk/savilerow-1.6.4-linux.tgz
# tar zxvf savilerow-1.6.4-linux.tgz
# cp savilerow-1.6.4-linux/savilerow.jar ${BIN_DIR}/savilerow.jar
# mkdir -p ${BIN_DIR}/lib
# cp savilerow-1.6.4-linux/lib/trove.jar ${BIN_DIR}/lib/trove.jar
# rm -rf savilerow-1.6.4-linux.tgz savilerow-1.6.4-linux

pushd ${BIN_DIR}
echo '#!/bin/bash'                                                               >  savilerow
echo 'DIR="$( cd "$( dirname "$0" )" && pwd )"'                                  >> savilerow
echo 'java -ea -XX:ParallelGCThreads=1 -Xmx8G -jar "$DIR/savilerow.jar" "$@"'    >> savilerow
chmod +x savilerow
popd

# using an unreleased version of savilerow
wget -c https://dl.dropboxusercontent.com/u/14272760/SavileRow/2017-04-23%2008-57%20726042477d4b/savilerow.jar
cp savilerow.jar ${BIN_DIR}/savilerow.jar
