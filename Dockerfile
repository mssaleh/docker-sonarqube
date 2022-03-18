FROM openjdk:11.0-jdk-slim-bullseye

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get full-upgrade -y \
    && apt-get autoremove -y --purge && apt-get autoclean -y && apt-get clean \
    && apt-get install -y --no-install-recommends \
      apt-transport-https \
      bash \
      curl \
      git \
      gnupg \
      gnupg-agent \
      gosu \
      fonts-dejavu \
      unzip \
      wget \
      xz-utils \
      zip \
    && curl -L https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg \
    && echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' | tee /etc/apt/sources.list.d/dart_stable.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends dart \
    && rm -rf \
        /tmp/* \
        /var/{cache,log}/* \
        /var/lib/apt/lists/* \
    && export PATH="$PATH:/usr/lib/dart/bin"

ARG FLUTTER_VERSION=2.10.3
RUN curl -L -o /flutter_linux_${FLUTTER_VERSION}-stable.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz \
    && cd / \
    && tar xf flutter_linux_${FLUTTER_VERSION}-stable.tar.xz \
    && rm /flutter_linux_${FLUTTER_VERSION}-stable.tar.xz \
    && ls -Al \
    && export PATH="$PATH:/flutter/bin" \
    && flutter precache

ARG SONAR_SCANNER_VERSION=4.7.0.2747
RUN curl -L -o /sonar-scanner-cli-${SONAR_SCANNER_VERSION}.zip https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}.zip \
    && unzip /sonar-scanner-cli-${SONAR_SCANNER_VERSION}.zip \
    && rm /sonar-scanner-cli-${SONAR_SCANNER_VERSION}.zip \
    && mv /sonar-scanner-${SONAR_SCANNER_VERSION} /sonar-scanner \
    && export PATH="$PATH:/sonar-scanner/bin"

#
# SonarQube setup
#
ARG SONARQUBE_VERSION=9.3.0.51899
ARG SONARQUBE_ZIP_URL=https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip
ENV SONARQUBE_HOME=/opt/sonarqube \
    SONAR_VERSION="${SONARQUBE_VERSION}" \
    SQ_DATA_DIR="/opt/sonarqube/data" \
    SQ_EXTENSIONS_DIR="/opt/sonarqube/extensions" \
    SQ_LOGS_DIR="/opt/sonarqube/logs" \
    SQ_TEMP_DIR="/opt/sonarqube/temp"

RUN set -eux; \
    groupadd -r -g 1000 sonarqube; \
    useradd -r -u 1000 -g 1000 sonarqube; \
    # pub   2048R/D26468DE 2015-05-25
    #       Key fingerprint = F118 2E81 C792 9289 21DB  CAB4 CFCA 4A29 D264 68DE
    # uid                  sonarsource_deployer (Sonarsource Deployer) <infra@sonarsource.com>
    # sub   2048R/06855C1D 2015-05-25
    echo "networkaddress.cache.ttl=5" >> "${JAVA_HOME}/conf/security/java.security"; \
    sed --in-place --expression="s?securerandom.source=file:/dev/random?securerandom.source=file:/dev/urandom?g" "${JAVA_HOME}/conf/security/java.security"; \
    for server in $(shuf -e hkps://keys.openpgp.org \
                            hkps://keyserver.ubuntu.com) ; do \
        gpg --batch --keyserver "${server}" --recv-keys 679F1EE92B19609DE816FDE81DB198F93525EC1A && break || : ; \
    done; \
    mkdir --parents /opt; \
    cd /opt; \
    curl --fail --location --output sonarqube.zip --silent --show-error "${SONARQUBE_ZIP_URL}"; \
    curl --fail --location --output sonarqube.zip.asc --silent --show-error "${SONARQUBE_ZIP_URL}.asc"; \
    gpg --batch --verify sonarqube.zip.asc sonarqube.zip; \
    unzip -q sonarqube.zip; \
    mv "sonarqube-${SONARQUBE_VERSION}" sonarqube; \
    rm sonarqube.zip*; \
    rm -rf ${SONARQUBE_HOME}/bin/*; \
    chown -R sonarqube:sonarqube ${SONARQUBE_HOME}; \
    ## maybe not needed
    chown -R sonarqube:sonarqube /flutter; \
    chown -R sonarqube:sonarqube /sonar-scanner; \
    # this 777 will be replaced by 700 at runtime (allows semi-arbitrary "--user" values)
    chmod -R 777 "${SQ_DATA_DIR}" "${SQ_EXTENSIONS_DIR}" "${SQ_LOGS_DIR}" "${SQ_TEMP_DIR}"

COPY --chown=sonarqube:sonarqube run.sh sonar.sh ${SONARQUBE_HOME}/bin/
RUN chmod a+x ${SONARQUBE_HOME}/bin/* \
    && chmod a+x /flutter/bin/* \
    && chmod a+x /sonar-scanner/bin/*

ENV PATH "$PATH:/sonar-scanner/bin:/flutter/bin:/usr/lib/dart/bin"

WORKDIR ${SONARQUBE_HOME}
EXPOSE 9000

STOPSIGNAL SIGINT

ENTRYPOINT ["/opt/sonarqube/bin/run.sh"]
CMD ["/opt/sonarqube/bin/sonar.sh"]
