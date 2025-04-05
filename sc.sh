#!/bin/bash

LOG_FILE="auto_hardening.log"
RESULTS_FILE="./resultat.txt"
WARNING_FILE="./warning.txt"
REPORT_FILE="./rapport.txt"
HEALTH_BEFORE=0
HEALTH_AFTER=0

# Fonction pour extraire le score de santé
get_healthiness() {
    sudo grep -Eo "Hardening index[[:space:]]*:[[:space:]]*[0-9]+" "$1" | awk -F: '{print $2}' | tr -d '[:space:]'
}

install_lynis() {
    if ! command -v lynis &> /dev/null; then
        echo "Lynis not found. Installing..." | sudo tee -a $LOG_FILE
        sudo apt-get update -qq && sudo apt-get install lynis -y
    fi
}

perform_audit() {
    echo "Running Lynis audit..." | sudo tee -a $LOG_FILE
    sudo lynis audit system > "$RESULTS_FILE"
    HEALTH_BEFORE=$(get_healthiness "$RESULTS_FILE")

    if [[ -z $HEALTH_BEFORE ]]; then
        echo "Error: Unable to retrieve healthiness score. Please check the Lynis output." | sudo tee -a $LOG_FILE
    else
        echo "Audit completed. Healthiness: $HEALTH_BEFORE%" | sudo tee -a $LOG_FILE
    fi

    sudo awk '/Warnings \([0-9]+\):/,/^$/ {if (!/^Warnings \([0-9]+\):/ && !/^$/) print}' "$RESULTS_FILE" > "$WARNING_FILE"

    if [[ ! -s $WARNING_FILE ]]; then
        echo "Aucun warning grave détecté." | sudo tee "$WARNING_FILE" > /dev/null
    fi
}

apply_corrections() {
    echo "Applying automatic corrections..." | sudo tee -a $LOG_FILE

    # Exemple de correctifs automatiques basés sur les recommandations courantes

    # 1. Configurer un mot de passe pour GRUB
    echo "Setting GRUB password..." | sudo tee -a $LOG_FILE
    sudo bash -c 'echo "set superusers=\"root\"\npassword_pbkdf2 root $(grub-mkpasswd-pbkdf2 <<<password)" >> /etc/grub.d/40_custom'
    sudo update-grub

    # 2. Activer le pare-feu UFW
    echo "Enabling UFW firewall..." | sudo tee -a $LOG_FILE
    sudo ufw allow ssh
    sudo ufw enable

    # 3. Renforcer les configurations SSH
    echo "Hardening SSH configuration..." | sudo tee -a $LOG_FILE
    sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
    sudo sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
    sudo systemctl restart sshd

    # 4. Installer et configurer Fail2Ban
    echo "Installing and configuring Fail2Ban..." | sudo tee -a $LOG_FILE
    sudo apt-get install fail2ban -y
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban

    # 5. Activer les mises à jour automatiques
    echo "Enabling automatic updates..." | sudo tee -a $LOG_FILE
    sudo apt-get install unattended-upgrades -y
    sudo dpkg-reconfigure --priority=low unattended-upgrades

    echo "Corrections completed." | sudo tee -a $LOG_FILE
}

generate_report() {
    echo "Generating report..." | sudo tee -a $LOG_FILE
    {
        echo "##########################################"
        echo "# Durcissement Automatique - Rapport     #"
        echo "##########################################"
        echo "Date : $(date)"
        echo ""
        echo "### Résultats de l'Audit ###"
        echo "---------------------------------"
        cat "$RESULTS_FILE"
        echo ""
        echo "### Warnings Restants ###"
        echo "-------------------------"
        cat "$WARNING_FILE"
        echo ""
        echo "### Suggestions de Sécurité ###"
        echo "------------------------------"
        sudo awk '/Suggestions \([0-9]+\):/,/^$/ {if (!/^Suggestions \([0-9]+\):/ && !/^$/) print}' "$RESULTS_FILE"
    } | sudo tee "$REPORT_FILE" > /dev/null
    echo "Report saved to $REPORT_FILE" | sudo tee -a $LOG_FILE
}

case "$1" in
    scan)
        install_lynis
        perform_audit
        echo "Scan completed. Healthiness: $HEALTH_BEFORE%" | sudo tee -a $LOG_FILE
        generate_report
        ;;
    corrige)
        install_lynis
        perform_audit
        echo "État de santé avant corrections : $HEALTH_BEFORE%" | sudo tee -a $LOG_FILE
        apply_corrections
        perform_audit
        HEALTH_AFTER=$(get_healthiness "$RESULTS_FILE")
        echo "Correction terminée. État de santé après corrections : $HEALTH_AFTER%" | sudo tee -a $LOG_FILE
        generate_report
        ;;
    *)
        echo "Usage: $0 [scan|corrige]"
        exit 1
        ;;
esac

echo "Script execution completed!"

