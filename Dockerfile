FROM keyfactor/ejbca-ce:8.3.2

WORKDIR /config

COPY config/certprofile_OnBoarding+Profile-626302406.xml certprofile_OnBoarding+Profile-626302406.xml
COPY config/certprofile_Onboarding+TLS+Profile-42350785.xml certprofile_Onboarding+TLS+Profile-42350785.xml
COPY config/certprofile_Simpl+Profile-858756178.xml certprofile_Simpl+Profile-858756178.xml
COPY config/entityprofile_Onboarding+End+Entity-260143312.xml entityprofile_Onboarding+End+Entity-260143312.xml

WORKDIR /
COPY entrypoint.sh entrypoint.sh
