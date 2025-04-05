#!/bin/bash

# Vérification des Arguments
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <BASTION_HOST_IP> <scan|corrige>"
    exit 1
fi

BASTION_IP="$1"                       # IP publique du Bastion passée en argument
OPERATION="$2"                        # Opération : scan ou corrige
BASTION_USER="ubuntu"                 # Utilisateur du Bastion Host
KEY_PATH="./os_hardening.pem"         # Chemin de la clé privée pour SSH
LOCAL_SCRIPT="./sc.sh"                # Script local à copier sur le Bastion
REMOTE_SCRIPT="/home/ubuntu/sc.sh"    # Chemin du script sur le Bastion
IP_FILE="./ip.txt"                    # Fichier contenant les IP des machines cibles
S3_BUCKET="s3://ebanking-reports"     # Nom du bucket S3

# Étape 1 : Transfert des fichiers vers le Bastion Host
echo "Transfert des fichiers sc.sh, ip.txt et clé SSH vers le Bastion Host ($BASTION_IP)..."
scp -i "$KEY_PATH" "$LOCAL_SCRIPT" "$IP_FILE" "$KEY_PATH" "$BASTION_USER@$BASTION_IP:/home/ubuntu/"
if [[ $? -ne 0 ]]; then
    echo "Erreur : Impossible de transférer les fichiers au Bastion Host."
    exit 1
fi

# Étape 2 : Connexion au Bastion et lancement du processus
echo "Connexion au Bastion Host et lancement du processus avec l'option '$OPERATION'..."
ssh -i "$KEY_PATH" "$BASTION_USER@$BASTION_IP" bash -s << EOF
    LOG_DIR="/home/ubuntu/output"
    mkdir -p \$LOG_DIR

    echo "Traitement des machines cibles à partir de ip.txt..."
    while read -r ip; do
        echo "Traitement de la machine cible : \$ip"

        # Transfert du script sc.sh vers la machine cible
        scp -i /home/ubuntu/os_hardening.pem /home/ubuntu/sc.sh ubuntu@\$ip:/home/ubuntu/sc.sh

        # Exécution du script sur la machine cible
        ssh -i /home/ubuntu/os_hardening.pem ubuntu@\$ip "sudo bash /home/ubuntu/sc.sh $OPERATION"

        # Récupération des fichiers générés
        mkdir -p \$LOG_DIR/\$ip
        scp -i /home/ubuntu/os_hardening.pem ubuntu@\$ip:/home/ubuntu/resultat.txt \$LOG_DIR/\$ip/resultat.txt
        scp -i /home/ubuntu/os_hardening.pem ubuntu@\$ip:/home/ubuntu/warning.txt \$LOG_DIR/\$ip/warning.txt
        scp -i /home/ubuntu/os_hardening.pem ubuntu@\$ip:/home/ubuntu/rapport.txt \$LOG_DIR/\$ip/rapport.txt

        # Nettoyage des fichiers sur la machine cible
        ssh -i /home/ubuntu/os_hardening.pem ubuntu@\$ip "rm -f /home/ubuntu/sc.sh /home/ubuntu/resultat.txt /home/ubuntu/warning.txt /home/ubuntu/rapport.txt"
    done < /home/ubuntu/ip.txt

    # Transfert des fichiers vers S3
    echo "Transfert des rapports vers le bucket S3 ($S3_BUCKET)..."
    aws s3 cp \$LOG_DIR $S3_BUCKET --recursive
    if [[ \$? -ne 0 ]]; then
        echo "Erreur : Échec du transfert vers S3."
        exit 1
    fi

    echo "Rapports transférés avec succès vers S3."
EOF

if [[ $? -ne 0 ]]; then
    echo "Erreur : Problème lors de l'exécution sur le Bastion Host."
    exit 1
fi

# Étape 3 : Nettoyer les fichiers temporaires sur le Bastion Host
echo "Nettoyage des fichiers temporaires sur le Bastion Host..."
ssh -i "$KEY_PATH" "$BASTION_USER@$BASTION_IP" "rm -rf /home/ubuntu/output /home/ubuntu/sc.sh /home/ubuntu/ip.txt /home/ubuntu/os_hardening.pem"

echo "Processus terminé. Les résultats sont sauvegardés dans le bucket S3 ($S3_BUCKET)."

