#!/usr/bin/env bash

set -e

mkdir -p $GUS_HOME/lib/perl/ApiCommonData/Load/Plugin

cd $PROJECT_HOME
git clone https://github.com/VEuPathDB/ApiCommonData.git
cd ApiCommonData
# webdb_workflow = postgres branch for plugins
git checkout webdb_workflow
git reset --hard $APICOMMONDATA_COMMIT_HASH
cp $PROJECT_HOME/ApiCommonData/Load/plugin/perl/*.pm $GUS_HOME/lib/perl/ApiCommonData/Load/Plugin/
cp -r $PROJECT_HOME/ApiCommonData/Load/lib/perl/* $GUS_HOME/lib/perl/ApiCommonData/Load/
cp -r $PROJECT_HOME/ApiCommonData/Load/bin/* $GUS_HOME/bin/

cd $PROJECT_HOME
git clone https://github.com/VEuPathDB/ClinEpiData.git
cd ClinEpiData
git reset --hard $CLINEPIDATA_GIT_COMMIT_SHA
bld ClinEpiData/Load

cd $PROJECT_HOME
git clone https://github.com/VEuPathDB/eda-nextflow.git
cd eda-nextflow
git reset --hard $EDA_NEXTFLOW_GIT_COMMIT_SHA
