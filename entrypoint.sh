#!/usr/bin/env bash

function sig_int() {
  echo "** SIGINT"
}

trap sig_int INT

function do_it () {
  local EJBCA_SH
  local K8S_VERSION
  local K

  local MANAGEMENTCA_ID
  local SIMPLCA_ID

  local CLIENT_CERT
  local CA_TRUSTSTORE

  if [ -z ${T1_GATEWAY+x} ]; then
    echo "T1_GATEWAY is unset";
    exit 1
  fi

  if [ -z ${NAMESPACE+x} ]; then
    echo "NAMESPACE is unset";
    exit 1
  fi

  if [ -z ${MANAGEMENT_END_ENTITY_USERNAME+x} ]; then
    echo "MANAGEMENT_END_ENTITY_USERNAME is unset";
    exit 1
  fi

  if [ -z ${MANAGEMENT_END_ENTITY_PASSWORD+x} ]; then
    echo "MANAGEMENT_END_ENTITY_PASSWORD is unset";
    exit 1
  fi

  EJBCA_SH=/opt/keyfactor/bin/ejbca.sh
  K8S_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

  curl -vLO "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
  K=/opt/keyfactor/kubectl
  chmod u+x "${K}"

  /opt/keyfactor/bin/start.sh > /opt/keyfactor/starting-ejbca.log 2>&1 &

  until [ -f /opt/keyfactor/appserver/standalone/deployments/ejbca.ear.deployed ]; do
    echo "waiting to start ejbca";
    sleep 5;
  done

  until "${EJBCA_SH}" roles listadmins --role "Super Administrator Role" | grep -vq 'USERNAME TYPE_EQUALCASE "ejbca"' ; do
    echo "waiting to have the super admin ready";
    sleep 5;
  done

  echo "super admin ready"
  sleep 5

  if ejbca.sh cryptotoken list | grep SimplCryptoToken >/dev/null 2>&1; then

    echo "ejbca already bootstrapped"
    exit 0;
  fi

  ###################
  # Enable REST API #
  ###################

  "${EJBCA_SH}" config protocols enable "REST Certificate Management"
  "${EJBCA_SH}" config protocols enable "REST Certificate Management V2"

  ###################
  # Import Profiles #
  ###################

  mkdir -p /opt/keyfactor/import/profiles

  cp -Rfv /config/* /opt/keyfactor/import/profiles

  echo "Reading /opt/keyfactor/import/profiles"
  head /opt/keyfactor/import/profiles/*
  echo "######################################"

  "${EJBCA_SH}" ca importprofiles /opt/keyfactor/import/profiles

  MANAGEMENTCA_ID="${EJBCA_SH}" ca info ManagementCA | grep "CA ID" | sed 's/.*CA ID: //'

  echo "Management CA Identifier"
  echo "${MANAGEMENTCA_ID}"
  echo "###########"

  ############
  # Simpl CA #
  ############

  "${EJBCA_SH}" cryptotoken create \
    --token SimplCryptoToken \
    --pin 987654321 \
    --autoactivate true \
    --type SoftCryptoToken
  "${EJBCA_SH}" cryptotoken generatekey \
    --token SimplCryptoToken \
    --alias SimplEncryptKey0001 \
    --keyspec secp256r1
  "${EJBCA_SH}" cryptotoken generatekey \
    --token SimplCryptoToken \
    --alias SimplSignKey0001 \
    --keyspec secp256r1
  "${EJBCA_SH}" cryptotoken generatekey \
    --token SimplCryptoToken \
    --alias testKey \
    --keyspec secp256r1

  {
    echo 'certSignKey SimplSignKey0001'
    echo 'crlSignKey SimplSignKey0001'
    echo 'keyEncryptKey SimplEncryptKey0001'
    echo 'testKey testKey'
    echo 'defaultKey SimplEncryptKey0001'
  } > /opt/keyfactor/simpl_crypto_token.properties

  echo "Reading /opt/keyfactor/simpl_crypto_token.properties"
  cat /opt/keyfactor/simpl_crypto_token.properties
  echo "####################################################"

  ejbca.sh ca init \
    --caname SimplCA \
    --dn CN=SimplCA \
    --tokenName SimplCryptoToken \
    -v 10950 \
    --policy null \
    -s SHA256withECDSA \
    --keytype ECDSA \
    --keyspec secp256r1 \
    --tokenprop /opt/keyfactor/simpl_crypto_token.properties \
    -certprofile "Simpl Profile"

  ejbca.sh ca editca SimplCA encodedValidity 30y
  ejbca.sh ca editca SimplCA useLdapDnOrder false
  ejbca.sh ca editca SimplCA CRLPeriod 7776000000

  SIMPLCA_ID=$("${EJBCA_SH}" ca info SimplCA | grep "CA ID" | sed 's/.*CA ID: //')

  echo "SimplCA Identifier"
  echo "${SIMPLCA_ID}"
  echo "###########"

  #################
  # OnBoardingCA  #
  #################

  "${EJBCA_SH}" cryptotoken create \
    --token SimplOnboardingCryptoToken \
    --pin 987654321 \
    --autoactivate true \
    --type SoftCryptoToken
  "${EJBCA_SH}" cryptotoken generatekey \
    --token SimplOnboardingCryptoToken \
    --alias SimplOnboardingEncryptKey001 \
    --keyspec secp256r1
  "${EJBCA_SH}" cryptotoken generatekey \
    --token SimplOnboardingCryptoToken \
    --alias SimplOnboardingSignKey001 \
    --keyspec secp256r1
  "${EJBCA_SH}" cryptotoken generatekey \
    --token SimplOnboardingCryptoToken \
    --alias SimplOnboardingTestKey001 \
    --keyspec secp256r1

  {
    echo 'certSignKey SimplOnboardingSignKey001'
    echo 'crlSignKey SimplOnboardingSignKey001'
    echo 'keyEncryptKey SimplOnboardingEncryptKey001'
    echo 'testKey SimplOnboardingTestKey001'
    echo 'defaultKey SimplOnboardingEncryptKey001'
  } > /opt/keyfactor/simpl_onboarding_crypto_token.properties

  echo "Reading /opt/keyfactor/simpl_onboarding_crypto_token.properties"
  cat /opt/keyfactor/simpl_onboarding_crypto_token.properties
  echo "####################################################"

  "${EJBCA_SH}" ca init \
    --caname OnBoardingCA \
    --dn CN=OnBoardingCA \
    --tokenName SimplOnboardingCryptoToken \
    -v 10950 \
    --policy null \
    -s SHA256withECDSA \
    --keytype ECDSA \
    --keyspec secp256r1 \
    --tokenprop /opt/keyfactor/simpl_onboarding_crypto_token.properties \
    -certprofile "OnBoarding Profile" \
    --signedby "${SIMPLCA_ID}"

  "${EJBCA_SH}" ca editca OnBoardingCA encodedValidity 15y
  "${EJBCA_SH}" ca editca OnBoardingCA useLdapDnOrder false
  "${EJBCA_SH}" ca editca OnBoardingCA CRLPeriod 7776000000
  "${EJBCA_SH}" ca editca OnBoardingCA CRLIssueInterval 86400000
  "${EJBCA_SH}" ca editca OnBoardingCA CRLOverlapTime 0

  "${EJBCA_SH}" ca editca OnBoardingCA doEnforceUniquePublicKeys false
  "${EJBCA_SH}" ca editca OnBoardingCA doEnforceUniqueDistinguishedName false

  "${EJBCA_SH}" ca editca OnBoardingCA defaultCRLDistPoint "https://${T1_GATEWAY}/crl/OnBoardingCA"
  "${EJBCA_SH}" ca editca OnBoardingCA defaultOCSPServiceLocator "https://${T1_GATEWAY}/ocsp"
  "${EJBCA_SH}" ca editca OnBoardingCA certificateAiaDefaultCaIssuerUri "https://${T1_GATEWAY}/ca/OnBoardingCA"

  #################
  #   MNGT USER   #
  #################
  if ! "${K}" -n "${NAMESPACE}" get secret ejbca-rest-api-secret >/dev/null 2>&1; then
    "${EJBCA_SH}" ra addendentity \
      --username "${MANAGEMENT_END_ENTITY_USERNAME}" \
      --dn "CN=${MANAGEMENT_END_ENTITY_USERNAME}" \
      --caname 'ManagementCA' \
      --type 1 \
      --token P12 \
      --altname "dNSName=${MANAGEMENT_END_ENTITY_USERNAME}" \
      --certprofile ENDUSER \
      --password "${MANAGEMENT_END_ENTITY_PASSWORD}"

    "${EJBCA_SH}" roles addrolemember \
      --role 'Super Administrator Role' \
      --caname ManagementCA \
      --with WITH_COMMONNAME \
      --value "${MANAGEMENT_END_ENTITY_USERNAME}" \
      --provider ""

    "${EJBCA_SH}" ra setendentitystatus \
      --username "${MANAGEMENT_END_ENTITY_USERNAME}" \
      -S 10

    "${EJBCA_SH}" ra setclearpwd \
      "${MANAGEMENT_END_ENTITY_USERNAME}" "${MANAGEMENT_END_ENTITY_PASSWORD}"

    "${EJBCA_SH}" batch \
      "${MANAGEMENT_END_ENTITY_USERNAME}"

    curl -Lk "https://localhost:8443/ejbca/ra/cert?caid=$("${EJBCA_SH}" ca info ManagementCA | grep "CA ID" | sed 's/.*CA ID: //')&chain=true&format=jks" > /opt/keyfactor/p12/truststore.jks

    CLIENT_CERT=$(< "/opt/keyfactor/p12/${MANAGEMENT_END_ENTITY_USERNAME}.p12" base64)
    CA_TRUSTSTORE=$(< /opt/keyfactor/p12/truststore.jks base64)

    echo "Management Keystore"
    echo "${CLIENT_CERT}"
    echo "###################"

    echo "Management Truststore"
    echo "${CA_TRUSTSTORE}"
    echo "#####################"

    "${K}" -n "${NAMESPACE}" create secret generic ejbca-rest-api-secret \
      --from-file=client-cert="/opt/keyfactor/p12/${MANAGEMENT_END_ENTITY_USERNAME}.p12" \
      --from-file=ca-truststore=/opt/keyfactor/p12/truststore.jks
  else
    echo "Nothing to do with managment for ejbca"
  fi
}

do_it "$@"
