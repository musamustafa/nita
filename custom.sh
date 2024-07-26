#!/bin/bash

# @(#) install.sh - NITA installation script

# Written by us, so that you don't have to

# ------------------------------------------------------------------------------
# Define functions and variables

ME="${0##*/}"                           # This scripts name
HOST=`uname -n`
REALUSER="${SUDO_USER:-${USER}}"        # User behind sudo
bold=$(tput bold)                       # For echo emphasis
normal=$(tput sgr0)
PATH=${PATH:="/bin:/usr/bin:/usr/sbin"} # Set out base path from the parent

# Define recommended values (in GB)

RECOMMENDED_MEMORY=8                    # Recommended memory
RECOMMENDED_DISK=10                     # Recommended free disk space

# Note: Set IGNORE_WARNINGS to true to continue regardless

# Set these env vars or take them from the calling shell

NITAROOT=${NITAROOT:=/opt}              # Where to install NITA
NITAPROJECT=${NITAPROJECT:=/var/nita_project}    # Home of NITA project files
BINDIR=${BINDIR:=/usr/local/bin}        # Where to put binaries
BASH_COMPLETION=${BASH_COMPLETION:="/etc/bash_completion.d"}
JAVA_HOME=${JAVA_HOME:=$NITAROOT/jdk-19.0.1}

K8SROOT=${K8SROOT:=$NITAROOT/nita/k8s}
PROXY=${PROXY:=$K8SROOT/proxy}
CERTS=${CERTS:=$PROXY/certificates}
JENKINS=${JENKINS:=/var/jenkins_home}
KEYPASS=${KEYPASS:="nita123"}

KUBEROOT=${KUBEROOT:=/etc/kubernetes}
KUBECONFIG=${KUBECONFIG:=$KUBEROOT/admin.conf}

PATH=${PATH}:${JAVA_HOME}/bin
export OWNER_HOME=`egrep "^${REALUSER}" /etc/passwd | awk -F: '{print $6}'`
export PATH NITAROOT KUBEROOT K8SROOT PROXY CERTS JENKINS KEYPASS KUBECONFIG JAVA_HOME

Question () {

    # Ask a yes/no/quit question. Default answer is "No"

    echo -n "$1 (y|n|q)? [n] "

    read ANSWER
    ANSWER=${ANSWER:="n"}

    [ "X$ANSWER" = "Xy" ] || [ "X$ANSWER" = "XY" ] && {
        return 0
    }

    [ "X$ANSWER" = "Xq" ] || [ "X$ANSWER" = "XQ" ] && {
        echo "Goodbye!"
        exit 0
    }

    return 1
}

Verify() {

    # Check that a named file exists

    if [ ! -x "$(command -v $1)" ]; then

        echo "Error: Cannot find command \"$1\"."
        exit 1

    else

        Debug "echo $1 exists"
    fi

}

Debug() {

    # Execute debug commands if DEBUG is set in the shell

    [ ${DEBUG} ] && {
        echo "${ME}: DEBUG: $*" >&2
        eval "$*" >&2
    }

    return $?
}

# ------------------------------------------------------------------------------
# Check the user and the environment we are running on

echo "${ME}: NITA install script."


Debug "echo $PATH"
Debug "echo $NITAROOT $KUBEROOT $K8SROOT $PROXY $CERTS $JENKINS $KEYPASS $KUBECONFIG $JAVA_HOME"

ARCH=`uname -m`
MEM=`free -g | grep Mem | awk '{print $2}'`
DISK=`df -h --output='avail' /var | sed 1d | sed 's/.$//'`

Debug "echo The CPU architecture is ${ARCH}"
Debug "echo Free memory is ${MEM}GB"
Debug "echo Free disk space is ${DISK}GB"


INSTALLER="apt install -y"
UPDATE="apt update -y"


[ "X${ARCH}" != "Xx86_64" ] && {
    echo "Warning: NITA has not been tested on this architecture"
    [ ! ${IGNORE_WARNINGS} ] && exit
}

[[ "${MEM}" -lt ${RECOMMENDED_MEMORY} ]] && {
    echo "Warning: Available memory is below recommended amount of ${RECOMMENDED_MEMORY}GB"
    [ ! ${IGNORE_WARNINGS} ] && exit
}

[[ "${DISK}" -lt ${RECOMMENDED_DISK} ]] && {
    echo "Warning: Available storage space is below recommended amount of ${RECOMMENDED_DISK}GB"
    [ ! ${IGNORE_WARNINGS} ] && exit
}

# ------------------------------------------------------------------------------
# Main part of the script

# ------------------------------------------------------------------------------

Question "Install NITA repositories" && {

    mkdir -p ${BINDIR}

    NITA_REPOS="nita nita-ansible nita-jenkins nita-robot nita-webapp"

    for REPO in ${NITA_REPOS}; do
 
        # Note: git won't clone into an existing directory 
        # but we check anway and avoid pre-existing

        if [ ! -d ${NITAROOT}/${REPO} ]; then

            echo "${ME}: Cloning fresh repository: ${REPO}"

            git clone https://github.com/Juniper/${REPO}.git ${NITAROOT}/${REPO}

            # Make symbolic links for nita cli scripts...

            find ${NITAROOT}/${REPO}/cli_scripts -type f -name "nita-cmd*" -exec ln -s {} ${BINDIR} \;
            chmod 755 ${NITAROOT}/${REPO}/cli_scripts/nita-cmd*
        else
            echo "${ME}: Warning: Directory already exists: \"${NITAROOT}/${REPO}\". Skipping."
        fi
    done

    echo "${ME}: Executing NITA post-install scripts"

    NITACMD="${NITAROOT}/nita-webapp/nita-cmd"

    [ -d ${NITACMD} ] && {

        # Set up nita-cmd

        install -m 755 ${NITACMD}/cli_runner ${BINDIR}/nita-cmd
        install -m 644 ${NITACMD}/bash_completion.d/cli_runner_completions ${BASH_COMPLETION}/cli_runner_completions
        install -m 644 ${NITACMD}/bash_completion.d/nita-cmd ${BASH_COMPLETION}/nita-cmd

    }

    echo "${ME}: Making ${NITAPROJECT}"
    mkdir -p ${NITAPROJECT}

    cd  ${K8SROOT}
    bash apply-k8s.sh

    mkdir -p ${NITAROOT}/nita/k8s/proxy
    wget --inet4-only https://raw.githubusercontent.com/Juniper/nita-webapp/main/nginx/nginx.conf -O ${PROXY}/nginx.conf
    # ln -s ${NITAROOT}/nita/k8s/proxy ${PROXY}/nginx.conf

    Debug "kubectl get nodes -o wide"
    Debug "kubectl get pods -n nita"

    echo "${ME}: Generating nginx certificates."
    mkdir -p ${CERTS}
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ${CERTS}/nginx-certificate-key.key -out ${CERTS}/nginx-certificate.crt

    echo "${ME}: Creating config maps for proxy pod"
    kubectl create cm proxy-config-cm --from-file=${PROXY}/nginx.conf --namespace nita
    kubectl create cm proxy-cert-cm --from-file=${CERTS}/ --namespace nita

    echo "${ME}: Generating Jenkins keystore."
    Debug "echo In ${JENKINS}"
    # Note that keys and certs must be stored in the same directory as is referenced in the YAML configs
    mkdir -p ${JENKINS}
    Verify keytool
    keytool -genkey -keyalg RSA -alias selfsigned -keystore ${JENKINS}/jenkins_keystore.jks -keypass ${KEYPASS} -keysize 4096 -dname "cn=jenkins, ou=, o=, l=, st=, c=" -storepass ${KEYPASS} -srckeypass ${KEYPASS}

    keytool -importkeystore -srckeystore ${JENKINS}/jenkins_keystore.jks -destkeystore ${JENKINS}/jenkins.p12 -deststoretype PKCS12 -deststorepass ${KEYPASS}  -srcstorepass ${KEYPASS}

    echo "${ME}: Converting Jenkins keystore to certificate"
    openssl pkcs12 -in ${JENKINS}/jenkins.p12 -nokeys -out ${JENKINS}/jenkins.crt -password pass:${KEYPASS}

    echo "${ME}: Creating config maps for Jenkins pod"
    kubectl create cm jenkins-crt --from-file=${JENKINS}/jenkins.crt --namespace nita
    kubectl create cm jenkins-keystore --from-file=${JENKINS}/jenkins_keystore.jks --namespace nita

    echo "${ME}: Please wait ${bold}5-10 minutes${normal} for the Kubernetes pods to initialise"

    Debug "kubectl get cm"
    Debug "kubectl describe cm"
    Debug "kubectl get ns nita"

    # Finally, copy the K8S admin file to the local user and set ownership and update bashrc

    echo "${ME}: Creating a local ${OWNER_HOME}/.kube"
    mkdir -p ${OWNER_HOME}/.kube
    cp -i ${KUBEROOT}/admin.conf ${OWNER_HOME}/.kube/config
    chown -R $(id -u ${REALUSER}):$(id -g ${REALUSER}) ${OWNER_HOME}/.kube/
    echo "export PATH=\${PATH}:/usr/local/bin"  >> ${OWNER_HOME}/.bashrc
    echo "export KUBECONFIG=${OWNER_HOME}/.kube/config" >> ${OWNER_HOME}/.bashrc

    echo "${ME}: Now ${bold}source your bashrc file${normal} to set KUBECONFIG in your shell"

}

Question "Do you want to run Ansible as a standalone Docker container" && {

    # Running standalone Ansible containers requires docker

    eval "${INSTALLER} docker-ce"

    # This step will avoid the need to be a sudoer

    echo "${ME}: Adding user \"${REALUSER}\" to the docker group"
    usermod -aG docker ${REALUSER}

}

Debug "ls -al ${NITAROOT}"

echo "${ME}: NITA installation has finished."
echo ""
echo "${ME}: Remember to ${bold}source your bashrc file${normal} to set KUBECONFIG in your shell"
echo "${ME}: You can access the NITA webapp at https://${HOST}:443"
echo "${ME}: You can access the Jenkins UI at https://${HOST}:8443"
