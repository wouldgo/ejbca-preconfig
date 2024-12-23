#!/usr/bin/env bash

function do_it () {

  if [ -z ${MANAGEMENT_END_ENTITY_USERNAME+x} ] ||
    [ -z ${MANAGEMENT_END_ENTITY_PASSWORD+x} ] ||
    [ -z ${T1_GATEWAY+x} ] ||
    [ -z ${NAMESPACE+x} ]; then
    echo "Required env variables are: MANAGEMENT_END_ENTITY_USERNAME, MANAGEMENT_END_ENTITY_PASSWORD, T1_GATEWAY, NAMESPACE"
    exit 1
  fi

  /opt/keyfactor/bin/start.sh > /opt/keyfactor/starting-ejbca.log 2>&1 &

  until [ -f /opt/keyfactor/appserver/standalone/deployments/ejbca.ear.deployed ]; do echo "waiting to start ejbca"; sleep 5; done
  until [[ $(/opt/keyfactor/bin/ejbca.sh roles listadmins --role "Super Administrator Role" | grep -v 'USERNAME TYPE_EQUALCASE "ejbca"') ]]; do echo "waiting to have the super admin ready"; sleep 5; done

  sleep 5

  if ejbca.sh cryptotoken list | grep SimplCryptoToken >/dev/null 2>&1; then

    echo "ejbca already bootstrapped"
    exit 0;
  fi


  ###################
  # Enable REST API #
  ###################

  /opt/keyfactor/bin/ejbca.sh config protocols enable "REST Certificate Management"
  /opt/keyfactor/bin/ejbca.sh config protocols enable "REST Certificate Management V2"

  ###################
  # Import Profiles #
  ###################

  mkdir -pv /opt/keyfactor/import/profiles

  cp -vf config/certprofile_OnBoarding+Profile-626302406.xml /opt/keyfactor/import/profiles/certprofile_OnBoarding+Profile-626302406.xml
  echo "Reading /opt/keyfactor/import/profiles/certprofile_OnBoarding+Profile-626302406.xml"
  cat "/opt/keyfactor/import/profiles/certprofile_OnBoarding+Profile-626302406.xml"
  echo "#####################################################################"

  cp -vf config/certprofile_Onboarding+TLS+Profile-42350785.xml /opt/keyfactor/import/profiles/certprofile_Onboarding+TLS+Profile-42350785.xml
  echo "Reading /opt/keyfactor/import/profiles/certprofile_Onboarding+TLS+Profile-42350785.xml"
  cat "/opt/keyfactor/import/profiles/certprofile_Onboarding+TLS+Profile-42350785.xml"
  echo "#####################################################################"

  cp -vf config/certprofile_Simpl+Profile-858756178.xml /opt/keyfactor/import/profiles/certprofile_Simpl+Profile-858756178.xml
  echo "Reading /opt/keyfactor/import/profiles/certprofile_Simpl+Profile-858756178.xml"
  cat "/opt/keyfactor/import/profiles/certprofile_Simpl+Profile-858756178.xml"
  echo "#####################################################################"

  cp -vf config/entityprofile_Onboarding+End+Entity-260143312.xml /opt/keyfactor/import/profiles/entityprofile_Onboarding+End+Entity-260143312.xml
  echo "Reading /opt/keyfactor/import/profiles/entityprofile_Onboarding+End+Entity-260143312.xml"
  cat "/opt/keyfactor/import/profiles/entityprofile_Onboarding+End+Entity-260143312.xml"
  echo "#####################################################################"

  sleep 5

  /opt/keyfactor/bin/ejbca.sh ca importprofiles /opt/keyfactor/import/profiles || true

  ############
  # Simpl CA #
  ############

  /opt/keyfactor/bin/ejbca.sh cryptotoken create \
    --token SimplCryptoToken \
    --pin 987654321 \
    --autoactivate true \
    --type SoftCryptoToken || true
  /opt/keyfactor/bin/ejbca.sh cryptotoken generatekey \
    --token SimplCryptoToken \
    --alias SimplEncryptKey0001 \
    --keyspec secp256r1 || true
  /opt/keyfactor/bin/ejbca.sh cryptotoken generatekey \
    --token SimplCryptoToken \
    --alias SimplSignKey0001 \
    --keyspec secp256r1 || true
  /opt/keyfactor/bin/ejbca.sh cryptotoken generatekey \
    --token SimplCryptoToken \
    --alias testKey \
    --keyspec secp256r1 || true

  {
    echo 'certSignKey SimplSignKey0001'
    echo 'crlSignKey SimplSignKey0001'
    echo 'keyEncryptKey SimplEncryptKey0001'
    echo 'testKey testKey'
    echo 'defaultKey SimplEncryptKey0001'
  } > /opt/keyfactor/token.properties

  ejbca.sh ca init \
    --caname SimplCA \
    --dn CN=SimplCA \
    --tokenName SimplCryptoToken \
    -v 10950 \
    --policy null \
    -s SHA256withECDSA \
    --keytype ECDSA \
    --keyspec secp256r1 \
    --tokenprop /opt/keyfactor/token.properties -certprofile "Simpl Profile" || true

  ejbca.sh ca editca SimplCA encodedValidity 30y
  ejbca.sh ca editca SimplCA useLdapDnOrder false
  ejbca.sh ca editca SimplCA CRLPeriod 7776000000

  #################
  # OnBoardingCA  #
  #################

  /opt/keyfactor/bin/ejbca.sh cryptotoken create \
    --token SimplOnboardingCryptoToken \
    --pin 987654321 \
    --autoactivate true \
    --type SoftCryptoToken || true
  /opt/keyfactor/bin/ejbca.sh cryptotoken generatekey \
    --token SimplOnboardingCryptoToken \
    --alias SimplOnboardingEncryptKey001 \
    --keyspec secp256r1 || true
  /opt/keyfactor/bin/ejbca.sh cryptotoken generatekey \
    --token SimplOnboardingCryptoToken \
    --alias SimplOnboardingSignKey001 \
    --keyspec secp256r1 || true
  /opt/keyfactor/bin/ejbca.sh cryptotoken generatekey \
    --token SimplOnboardingCryptoToken \
    --alias SimplOnboardingTestKey001 \
    --keyspec secp256r1 || true

  {
    echo 'certSignKey SimplOnboardingSignKey001'
    echo 'crlSignKey SimplOnboardingSignKey001'
    echo 'keyEncryptKey SimplOnboardingEncryptKey001'
    echo 'testKey SimplOnboardingTestKey001'
    echo 'defaultKey SimplOnboardingEncryptKey001'
  } > /opt/keyfactor/token1.properties

  SimplCA_ID=$(/opt/keyfactor/bin/ejbca.sh ca info SimplCA | grep "CA ID" | sed 's/.*CA ID: //')

  /opt/keyfactor/bin/ejbca.sh ca init \
    --caname OnBoardingCA \
    --dn CN=OnBoardingCA \
    --tokenName SimplOnboardingCryptoToken \
    -v 10950 \
    --policy null \
    -s SHA256withECDSA \
    --keytype ECDSA \
    --keyspec secp256r1 \
    --tokenprop /opt/keyfactor/token1.properties \
    -certprofile "OnBoarding Profile" \
    --signedby "${SimplCA_ID}" || true

  /opt/keyfactor/bin/ejbca.sh ca editca OnBoardingCA encodedValidity 15y
  /opt/keyfactor/bin/ejbca.sh ca editca OnBoardingCA useLdapDnOrder false
  /opt/keyfactor/bin/ejbca.sh ca editca OnBoardingCA CRLPeriod 7776000000
  /opt/keyfactor/bin/ejbca.sh ca editca OnBoardingCA CRLIssueInterval 86400000
  /opt/keyfactor/bin/ejbca.sh ca editca OnBoardingCA CRLOverlapTime 0

  /opt/keyfactor/bin/ejbca.sh ca editca OnBoardingCA doEnforceUniquePublicKeys false
  /opt/keyfactor/bin/ejbca.sh ca editca OnBoardingCA doEnforceUniqueDistinguishedName false

  /opt/keyfactor/bin/ejbca.sh ca editca OnBoardingCA defaultCRLDistPoint "https://${T1_GATEWAY}/crl/OnBoardingCA"
  /opt/keyfactor/bin/ejbca.sh ca editca OnBoardingCA defaultOCSPServiceLocator "https://${T1_GATEWAY}/ocsp"
  /opt/keyfactor/bin/ejbca.sh ca editca OnBoardingCA certificateAiaDefaultCaIssuerUri "https://${T1_GATEWAY}/ca/OnBoardingCA"

  curl -vLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod u+x /opt/keyfactor/kubectl

  #################
  #   MNGT USER   #
  #################
  if ! /opt/keyfactor/kubectl -n "${NAMESPACE}" get secret ejbca-rest-api-secret >/dev/null 2>&1; then
    /opt/keyfactor/bin/ejbca.sh ra addendentity \
      --username "${MANAGEMENT_END_ENTITY_USERNAME}" \
      --dn "CN=${MANAGEMENT_END_ENTITY_USERNAME}" \
      --caname 'ManagementCA' \
      --type 1 \
      --token P12 \
      --altname "dNSName=${MANAGEMENT_END_ENTITY_USERNAME}" \
      --certprofile ENDUSER \
      --password "${MANAGEMENT_END_ENTITY_PASSWORD}"

    /opt/keyfactor/bin/ejbca.sh roles addrolemember \
      --role 'Super Administrator Role' \
      --caname ManagementCA \
      --with WITH_COMMONNAME \
      --value "${MANAGEMENT_END_ENTITY_USERNAME}" \
      --provider ""

    /opt/keyfactor/bin/ejbca.sh ra setendentitystatus \
      --username "${MANAGEMENT_END_ENTITY_USERNAME}" \
      -S 10

    /opt/keyfactor/bin/ejbca.sh ra setclearpwd \
      "${MANAGEMENT_END_ENTITY_USERNAME}" "${MANAGEMENT_END_ENTITY_PASSWORD}"

    /opt/keyfactor/bin/ejbca.sh batch \
      "${MANAGEMENT_END_ENTITY_USERNAME}"

    curl -Lk "https://localhost:8443/ejbca/ra/cert?caid=$(/opt/keyfactor/bin/ejbca.sh ca info ManagementCA | grep "CA ID" | sed 's/.*CA ID: //')&chain=true&format=jks" > /opt/keyfactor/p12/truststore.jks

    local CLIENT_CERT
    local CA_TRUSTSTORE
    CLIENT_CERT=$(< "/opt/keyfactor/p12/${MANAGEMENT_END_ENTITY_USERNAME}.p12" base64)
    CA_TRUSTSTORE=$(< /opt/keyfactor/p12/truststore.jks base64)
    echo "###################### MANAGEMENT"
    echo "${CLIENT_CERT}"
    echo "###################### TRUSTSTORE"
    echo "${CA_TRUSTSTORE}"

    /opt/keyfactor/kubectl -n "${NAMESPACE}" create secret generic ejbca-rest-api-secret \
      --from-file=client-cert="/opt/keyfactor/p12/${MANAGEMENT_END_ENTITY_USERNAME}.p12" \
      --from-file=ca-truststore=/opt/keyfactor/p12/truststore.jks
  else
    echo "Nothing to do with managment for ejbca"
  fi

}

do_it "$@"
