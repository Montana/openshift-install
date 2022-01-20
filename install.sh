#!/bin/bash

set +x

EAP_VERSION=1.0

expose_openshift_internal_registry() {
        OPENSHIFT_URL=$(oc whoami --show-server)
        oc patch configs.imageregistry.operator.openshift.io/cluster -p='{"spec":{"defaultRoute":true}}' --type=merge
        oc create serviceaccount registry || echo "Service Account registry already exists"
        oc adm policy add-cluster-role-to-user admin -z registry
        OPENSHIFT_REGISTRY_URL=$(oc get route -n openshift-image-registry -o jsonpath="{.items[0].spec.host}")
        docker login $OPENSHIFT_REGISTRY_URL -u registry -p $(oc sa get-token registry)
}

# Push them to OpenShift internal image registry as ImageStream tags for their corresponding image streams

import_eap_images_from_registry() {
        REGISTRY_PROXY=registry-proxy.engineering.redhat.com/rh-osbs
        OPENSHIFT_REGISTRY_URL=$(oc get route -n openshift-image-registry -o jsonpath="{.items[0].spec.host}")

        for jdk in "openjdk8-openshift-rhel7" "openjdk11-openshift-rhel8"; do

                EAP_IMAGE_FROM_PROXY=jboss-eap-7-eap-xp1-${jdk}:${EAP_VERSION}
                EAP_IST=jboss-eap-xp1-${jdk}
                EAP_IST=${EAP_IST%-rhel*}:${EAP_VERSION}

                for type in "openshift" "runtime-openshift"; do

                        dockerImage=${EAP_IMAGE_FROM_PROXY/openshift/$type}
                        ist=${EAP_IST/openshift/$type}

                        echo "Push ${dockerImage} to OpenShift ImageStreamTag ${ist}..."
                        docker pull ${REGISTRY_PROXY}/${dockerImage}
                        docker tag ${REGISTRY_PROXY}/${dockerImage} ${OPENSHIFT_REGISTRY_URL}/openshift/${ist}
                        docker push ${OPENSHIFT_REGISTRY_URL}/openshift/${ist}
                done
        done
}

import_eap_image_streams() {
        TEMPLATE_BRANCH=eap-xp1
        if [ ! -z "$dev" ]; then
                TEMPLATE_BRANCH=${TEMPLATE_BRANCH}-dev
        fi
        oc replace --force -n openshift -f https://raw.githubusercontent.com/jboss-container-images/jboss-eap-openshift-templates/${TEMPLATE_BRANCH}/jboss-eap-xp1-openjdk11-openshift.json
        oc replace --force -n openshift -f https://raw.githubusercontent.com/jboss-container-images/jboss-eap-openshift-templates/${TEMPLATE_BRANCH}/jboss-eap-xp1-openjdk8-openshift.json

        for resource in eap-xp1-amq-s2i.json \
                eap-xp1-basic-s2i.json \
                eap-xp1-third-party-db-s2i.json; do
                oc replace --force -f https://raw.githubusercontent.com/jboss-container-images/jboss-eap-openshift-templates/${TEMPLATE_BRANCH}/templates/${resource}
        done
}

expose_openshift_internal_registry
import_eap_image_streams
if [ ! -z "$proxy" ]; then
        import_eap_images_from_registry
fi
