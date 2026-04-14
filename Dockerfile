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
        cmake \
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

# Install R packages via apt (pre-compiled, much faster than CRAN)
RUN apt-get update && apt-get install -y \
        r-cran-abind \
        r-cran-askpass \
        r-cran-backports \
        r-cran-base64enc \
        r-cran-bh \
        r-cran-biocmanager \
        r-cran-bit \
        r-cran-bit64 \
        r-cran-bitops \
        r-cran-blob \
        r-cran-broom \
        r-cran-bslib \
        r-cran-cachem \
        r-cran-callr \
        r-cran-cellranger \
        r-cran-cli \
        r-cran-clipr \
        r-cran-conflicted \
        r-cran-cpp11 \
        r-cran-crayon \
        r-cran-curl \
        r-cran-data.table \
        r-cran-dbi \
        r-cran-dbplyr \
        r-cran-digest \
        r-cran-dplyr \
        r-cran-dtplyr \
        r-cran-evaluate \
        r-cran-farver \
        r-cran-fastmap \
        r-cran-fontawesome \
        r-cran-forcats \
        r-cran-formatr \
        r-cran-fs \
        r-cran-futile.logger \
        r-cran-futile.options \
        r-cran-gargle \
        r-cran-generics \
        r-cran-ggplot2 \
        r-cran-glue \
        r-cran-googledrive \
        r-cran-googlesheets4 \
        r-cran-gtable \
        r-cran-haven \
        r-cran-highr \
        r-cran-hms \
        r-cran-htmltools \
        r-cran-httr \
        r-cran-ids \
        r-cran-isoband \
        r-cran-jquerylib \
        r-cran-jsonlite \
        r-cran-knitr \
        r-cran-labeling \
        r-cran-lambda.r \
        r-cran-lifecycle \
        r-cran-locfit \
        r-cran-lubridate \
        r-cran-magrittr \
        r-cran-matrixstats \
        r-cran-memoise \
        r-cran-mime \
        r-cran-modelr \
        r-cran-openssl \
        r-cran-pillar \
        r-cran-pkgconfig \
        r-cran-prettyunits \
        r-cran-processx \
        r-cran-progress \
        r-cran-ps \
        r-cran-purrr \
        r-cran-r6 \
        r-cran-ragg \
        r-cran-rappdirs \
        r-cran-rcolorbrewer \
        r-cran-rcpp \
        r-cran-rcpparmadillo \
        r-cran-rcppeigen \
        r-cran-rcurl \
        r-cran-readr \
        r-cran-readxl \
        r-cran-rematch \
        r-cran-rematch2 \
        r-cran-repr \
        r-cran-reprex \
        r-cran-rlang \
        r-cran-rmarkdown \
        r-cran-rstudioapi \
        r-cran-rvest \
        r-cran-sass \
        r-cran-scales \
        r-cran-selectr \
        r-cran-skimr \
        r-cran-snow \
        r-cran-statmod \
        r-cran-stringi \
        r-cran-stringr \
        r-cran-sys \
        r-cran-systemfonts \
        r-cran-textshaping \
        r-cran-tibble \
        r-cran-tidyr \
        r-cran-tidyselect \
        r-cran-tidyverse \
        r-cran-timechange \
        r-cran-tinytex \
        r-cran-tzdb \
        r-cran-utf8 \
        r-cran-uuid \
        r-cran-vctrs \
        r-cran-viridislite \
        r-cran-vroom \
        r-cran-withr \
        r-cran-xfun \
        r-cran-xml2 \
        r-cran-yaml \
    && apt-get clean

## don't upgrade already-installed R packages (if they are sufficient)
ARG R_REMOTES_UPGRADE=never

# Install remaining CRAN dependencies not available via apt, plus remotes
# (apt version of remotes is too old to handle the 'huge=url' remote type)
# (same with igraph - needs to be 2.x)
RUN R -e "install.packages(c('remotes', 'S7', 'igraph'))"

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

ARG STUDY_WRANGLER_GIT_REF="v1.0.38"
RUN R -e "remotes::install_github('VEuPathDB/study-wrangler', '${STUDY_WRANGLER_GIT_REF}', upgrade_dependencies=F)"

# VDI PLUGIN SERVER
ARG PLUGIN_SERVER_VERSION=v1.7.0
RUN curl "https://github.com/VEuPathDB/vdi-service/releases/download/${PLUGIN_SERVER_VERSION}/plugin-server.tar.gz" -Lf --no-progress-meter | tar -xz

# scripts and paths

COPY ./ /opt/veupathdb/
ENV PATH="$PATH:/opt/veupathdb/bin"

CMD PLUGIN_ID=wrangler /startup.sh
