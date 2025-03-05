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

# # Install find-bin-width tool.
# RUN wget -q -O fbw.zip https://github.com/VEuPathDB/script-find-bin-width/releases/download/v1.0.3/fbw-linux-1.0.3.zip \
#     && unzip fbw.zip \
#     && rm fbw.zip \
#     && mv find-bin-width /usr/bin/find-bin-width


ARG SHARED_LIB_GIT_COMMIT_SHA=ee4853748fcdd5d7d8675eb0eb3828ea11da8f42

RUN git clone https://github.com/VEuPathDB/lib-vdi-plugin-study.git \
    && cd lib-vdi-plugin-study \
    && git checkout ${SHARED_LIB_GIT_COMMIT_SHA} \
    && mkdir -p /opt/veupathdb/lib/perl /opt/veupathdb/bin \
    && cp lib/perl/VdiStudyHandlerCommon.pm /opt/veupathdb/lib/perl \
    && cp bin/* /opt/veupathdb/bin


ARG APICOMMONDATA_COMMIT_HASH=699a94aab7c853205274aed2039ce0d2e4b76e30 \
    CLINEPIDATA_GIT_COMMIT_SHA=8d31ba1b5cf7f6b022058b7c89e8e3ab0665f543 \
    EDA_NEXTFLOW_GIT_COMMIT_SHA=f113cca94b9d16695dc4ac721de211d72e7c396f

# CLONE ADDITIONAL GIT REPOS
COPY bin/buildGus.bash /usr/bin/buildGus.bash
RUN /usr/bin/buildGus.bash


ARG PLUGIN_SERVER_VERSION=v8.1.1

# Install vdi plugin HTTP server
RUN set -o pipefail \
    && curl "https://github.com/VEuPathDB/vdi-plugin-handler-server/releases/download/${PLUGIN_SERVER_VERSION}/docker-download.sh" -Lf --no-progress-meter | bash

ENV PATH="$PATH:/opt/veupathdb/bin"

COPY bin /opt/veupathdb/bin/

## don't need geoMappings.xml?
# COPY lib/xml/* /usr/local/lib/xml/

RUN chmod +x /opt/veupathdb/bin/*

### study-wrangler and dependencies ###

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV CRAN="https://cloud.r-project.org"

# 24.10 is "oracular" but we need to use 24.04 "noble"
# because there are no R packages for non-LTS Ubuntu versions
ARG UBUNTU_CODENAME_FOR_R=noble


# Install system dependencies
RUN apt-get update && apt-get install -y \
    software-properties-common \
    dirmngr \
    curl \
    ca-certificates \
    gnupg \
    && curl -fsSL ${CRAN}/bin/linux/ubuntu/marutter_pubkey.asc | gpg --dearmor -o /usr/share/keyrings/cran-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cran-archive-keyring.gpg] ${CRAN}/bin/linux/ubuntu ${UBUNTU_CODENAME_FOR_R}-cran40/" > /etc/apt/sources.list.d/cran.list \
    && apt-get update \
    && apt-get install -y r-base r-base-dev

# Install Tidyverse from CRAN
RUN R -e "install.packages('tidyverse', repos='${CRAN}')"

# wrangler dependencies

### CRAN
RUN R -e "install.packages('skimr')"
RUN R -e "install.packages('remotes')"

### github
# plot.data dependencies not automatically installed:
RUN R -e "install.packages('BiocManager')"
RUN R -e "BiocManager::install('SummarizedExperiment')"
RUN R -e "BiocManager::install('DESeq2')"
RUN R -e "remotes::install_github('VEuPathDB/veupathUtils', 'v2.7.0', upgrade_dependencies=F)"

# plot.data for binwidth function
RUN R -e "remotes::install_github('VEuPathDB/plot.data', 'v5.4.2', upgrade_dependencies=F)"

# wrangler itself

# TO DO: tag a version - currently using latest from main
RUN R -e "remotes::install_github('VEuPathDB/study-wrangler', upgrade_dependencies=F)"


CMD ["run-plugin.sh"]
