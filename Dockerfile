FROM veupathdb/gus-apidb-base:1.2.7

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
    && apt-get install -y tzdata \
    && apt-get clean \
    && cp /usr/share/zoneinfo/America/New_York /etc/localtime \
    && echo ${TZ} > /etc/timezone

ARG LIB_VDI_PLUGIN_STUDY_GIT_REF="ee4853748fcdd5d7d8675eb0eb3828ea11da8f42"
RUN git clone https://github.com/VEuPathDB/lib-vdi-plugin-study.git \
    && cd lib-vdi-plugin-study \
    && git checkout ${LIB_VDI_PLUGIN_STUDY_GIT_REF} \
    && mkdir -p /opt/veupathdb/lib/perl /opt/veupathdb/bin \
    && cp lib/perl/VdiStudyHandlerCommon.pm /opt/veupathdb/lib/perl \
    && cp bin/* /opt/veupathdb/bin

### R installation takes a while so it goes first ###

## base R ##

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV CRAN="https://cloud.r-project.org"

# Base image Ubuntu 24.10 is "oracular" but we need to use 24.04 "noble"
# because there are no R packages for non-LTS Ubuntu versions
ARG UBUNTU_CODENAME_FOR_R=noble

# Install system dependencies
RUN apt-get update && apt-get install -y \
    software-properties-common \
    dirmngr \
    curl \
    ca-certificates \
    gnupg \
    libxml2-dev libcurl4-openssl-dev libssl-dev libglpk-dev \
    libfreetype6-dev libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
    libpng-dev libtiff5-dev libjpeg-dev \
    && curl -fsSL ${CRAN}/bin/linux/ubuntu/marutter_pubkey.asc | gpg --dearmor -o /usr/share/keyrings/cran-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cran-archive-keyring.gpg] ${CRAN}/bin/linux/ubuntu ${UBUNTU_CODENAME_FOR_R}-cran40/" > /etc/apt/sources.list.d/cran.list \
    && apt-get update \
    && apt-get install -y r-base r-base-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

## study-wrangler and dependencies ##

# Install Tidyverse from CRAN
RUN R -e "install.packages(c('tidyverse', 'skimr', 'remotes', 'BiocManager'))"

# plot.data dependencies not automatically installed:
RUN R -e "BiocManager::install('SummarizedExperiment')"
RUN R -e "BiocManager::install('DESeq2')"

ARG VEUPATHUTILS_GIT_REF="v2.7.0" \
    PLOT_DATA_GIT_REF="v5.4.2" \
    STUDY_WRANGLER_GIT_REF="01d9d0ce2b1190b8cd2dc2460852f0b0f27b44fd"
RUN R -e "remotes::install_github('VEuPathDB/veupathUtils', '${VEUPATHUTILS_GIT_REF}', upgrade_dependencies=F)"
# plot.data needed for binWidth function
RUN R -e "remotes::install_github('VEuPathDB/plot.data', '${PLOT_DATA_GIT_REF}', upgrade_dependencies=F)"
# and finally the wrangler itself
RUN R -e "remotes::install_github('VEuPathDB/study-wrangler', '${STUDY_WRANGLER_GIT_REF}', upgrade_dependencies=F)"

### end of R stuff ###

# Additional GUS repo checkouts
ARG APICOMMONDATA_COMMIT_HASH=699a94aab7c853205274aed2039ce0d2e4b76e30 \
    CLINEPIDATA_GIT_COMMIT_SHA=8d31ba1b5cf7f6b022058b7c89e8e3ab0665f543 \
    EDA_NEXTFLOW_GIT_COMMIT_SHA=f113cca94b9d16695dc4ac721de211d72e7c396f
COPY bin/buildGus.bash /usr/bin/buildGus.bash
RUN /usr/bin/buildGus.bash


# Install vdi plugin HTTP server
ARG PLUGIN_SERVER_VERSION="v8.1.1"
RUN set -o pipefail \
    && curl "https://github.com/VEuPathDB/vdi-plugin-handler-server/releases/download/${PLUGIN_SERVER_VERSION}/docker-download.sh" -Lf --no-progress-meter | bash


COPY bin /opt/veupathdb/bin/
RUN chmod +x /opt/veupathdb/bin/*
ENV PATH="$PATH:/opt/veupathdb/bin"

CMD ["run-plugin.sh"]
