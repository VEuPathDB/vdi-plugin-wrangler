FROM veupathdb/gus-apidb-base:1.2.12

ENV JVM_MEM_ARGS="-Xms16m -Xmx64m" \
    JVM_ARGS="" \
    TZ="America/New_York"

# ADDITIONAL PERL DEPENDENCIES
RUN perl -MCPAN -e 'install qq(Switch)' \
    && perl -MCPAN -e 'install qq(Config::Std)' \
    && perl -MCPAN -e 'install qq(Text::Unidecode)' \
    && perl -MCPAN -e 'install qq(Date::Calc)' \
    && perl -MCPAN -e 'install qq(XML::Simple)' \
    && perl -MCPAN -e 'install qq(Digest::SHA1)'

# Ensure we log in the correct timezone.
RUN apt-get update \
    && apt-get install -y \
        ca-certificates curl \
        dirmngr \
        gnupg \
        libxml2-dev libcurl4-openssl-dev libssl-dev libglpk-dev libjpeg-dev \
        libfreetype6-dev libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
        libpng-dev libtiff5-dev \
        software-properties-common \
        tzdata \
    && apt-get clean \
    && cp /usr/share/zoneinfo/America/New_York /etc/localtime \
    && echo ${TZ} > /etc/timezone

RUN apt-get update \
    && apt-get install -y r-base r-base-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


## non-veupathdb study-wrangler dependencies ##

# Install Tidyverse from CRAN
RUN R -e "install.packages(c('tidyverse', 'skimr', 'remotes', 'BiocManager', 'devtools'))"

# plot.data dependencies not automatically installed:
RUN R -e "BiocManager::install('SummarizedExperiment')"
RUN R -e "BiocManager::install('DESeq2')"

## veupathdb projects ##

# Additional GUS repo checkouts
ARG APICOMMONDATA_COMMIT_HASH=f7659ae9bede67f8848f7d01adfcbb09c50deae8 \
    CLINEPIDATA_GIT_COMMIT_SHA=8d31ba1b5cf7f6b022058b7c89e8e3ab0665f543 \
    EDA_NEXTFLOW_GIT_COMMIT_SHA=f113cca94b9d16695dc4ac721de211d72e7c396f
COPY bin/buildGus.bash /usr/bin/buildGus.bash
RUN /usr/bin/buildGus.bash

ARG LIB_VDI_PLUGIN_STUDY_GIT_REF="94274cbe2bee64e8e038e46f92b7a803fb48287a"
RUN git clone https://github.com/VEuPathDB/vdi-lib-plugin-eda.git \
    && cd vdi-lib-plugin-eda \
    && git checkout ${LIB_VDI_PLUGIN_STUDY_GIT_REF} \
    && mkdir -p /opt/veupathdb/lib/perl /opt/veupathdb/bin \
    && cp lib/perl/VdiStudyHandlerCommon.pm /opt/veupathdb/lib/perl \
    && cp bin/* /opt/veupathdb/bin

## study-wrangler and veupathdb R dependencies ##

ARG VEUPATHUTILS_GIT_REF="v2.7.0"
RUN R -e "remotes::install_github('VEuPathDB/veupathUtils', '${VEUPATHUTILS_GIT_REF}', upgrade_dependencies=F)"

# plot.data needed for binWidth function
ARG PLOT_DATA_GIT_REF="v5.4.2"
RUN R -e "remotes::install_github('VEuPathDB/plot.data', '${PLOT_DATA_GIT_REF}', upgrade_dependencies=F)"

# and finally the wrangler itself
ARG STUDY_WRANGLER_GIT_REF="v1.0.25"
RUN R -e "remotes::install_github('VEuPathDB/study-wrangler', '${STUDY_WRANGLER_GIT_REF}', upgrade_dependencies=F)"


# VDI PLUGIN SERVER
ARG PLUGIN_SERVER_VERSION=v1.7.0-a27
RUN curl "https://github.com/VEuPathDB/vdi-service/releases/download/${PLUGIN_SERVER_VERSION}/plugin-server.tar.gz" -Lf --no-progress-meter | tar -xz

# scripts and paths

COPY ./ /opt/veupathdb/
ENV PATH="$PATH:/opt/veupathdb/bin"

CMD PLUGIN_ID=wrangler run-plugin.sh
