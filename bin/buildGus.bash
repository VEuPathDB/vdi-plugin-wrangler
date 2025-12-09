#!/usr/bin/env bash

set -ex

mkdir -p $GUS_HOME/lib/perl/ApiCommonData/Load/

function dl() {
  wget -q "https://github.com/VEuPathDB/$1/archive/$2.zip"
  unzip -qq "$2.zip"
  rm "$2.zip"
  mv "$1-$2" "$1"
}

cd $PROJECT_HOME

dl ApiCommonData ${APICOMMONDATA_COMMIT_HASH}
ln -s $PROJECT_HOME/ApiCommonData/Load/plugin/perl $GUS_HOME/lib/perl/ApiCommonData/Load/Plugin
cp -r ApiCommonData/Load/lib/perl/* $GUS_HOME/lib/perl/ApiCommonData/Load/
cp -r ApiCommonData/Load/bin/* $GUS_HOME/bin/

dl ClinEpiData ${CLINEPIDATA_GIT_COMMIT_SHA}
bld ClinEpiData/Load

dl eda-nextflow ${EDA_NEXTFLOW_GIT_COMMIT_SHA}
