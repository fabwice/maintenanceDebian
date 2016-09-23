#!/bin/bash
# Script de backup quotidien d'un serveur rapsbian
#   Sauvegarde de la liste des packages installes
#   Sauvegarde de repertoires
#   Mise a jour des paquetages et firmware
#   Test du montage du disque usb
#   Temperature du raspberry pi 
#
# Written by Fabwice
# http://gwadanina.net

# ----------------------------------------------------------- #
#       Gestion des parametres de configuration               #
# ----------------------------------------------------------- #

# --------- Parametres du systeme
GZIP="$(which gzip)"
MKDIR="$(which mkdir)"
RSYNC="$(which rsync)"
SSH="$(which ssh)"
MAIL="$(which mail)"
TAR="$(which tar)"
TOUCH="$(which touch)"
RM="$(which rm)"
TRAP="$(which trap)"
FIND="$(which find)"
MD5SUM="$(which md5sum)"
HOSTNAME="$(hostname)"
TOUCH_REMOTE="/bin/touch"
DPKG="$(which dpkg)"

#--------- Date du jour
DATE_NOW="$(date +%Y-%m-%d)"
ANNEE_MOIS_NOW="$(date +%Y-%m)"

#--------- Configuration du serveur local
LOCAL_USER="archivekb"
LOCAL_GROUP="archivekb"
BACKUP_REPO="/home/$LOCAL_USER/BACKUP"
BACKUP_REPO_TMP="/home/$LOCAL_USER/tmp"
CURRENT_WORKING_REPO="$BACKUP_REPO/$ANNEE_MOIS_NOW/$DATE_NOW"
TMP_BACKUP_REPO="$BACKUP_REPO_TMP/backup_etc_modif_$DATE_NOW";
LOCKFILE="$CURRENT_WORKING_REPO/.lockfile"

# fichier de configuration local
CUSTOM_CONFIG="/etc/maintenance-service.cfg"

# --------- Configuration du serveur de backup distant
REMOTE_USER="archivekb"
REMOTE_HOST="gwadanina.net"
REMOTE_PORT=22
REMOTE_PATH="/home/$REMOTE_USER/backupdir"
REMOTE_PATH_FIN_DE_TRANSFERT="$REMOTE_PATH/BACKUP/$ANNEE_MOIS_NOW/$DATE_NOW/FIN_DE_TRANSFERT"

# ----------- Fichier de log de travail
LOG_INFO="$CURRENT_WORKING_REPO/backup_$DATE_NOW.log"

# -----------  Configuration de la conservation des fichiers
REPOSITORY_CHMOD="770"
LISTE_REPO_A_SAUVEGARDER="/etc/"

# --------- Configuration des Mails de notifications
NOTIFICATION_MAIL_IS_ACTIVE="yes"
NOTIFICATION_MAIL_ADRESSES="archivekb@gwadanina.net_"
NOTIFICATION_MAIL_SUJET="[BACKUP-$HOSTNAME]"

# --------- Nombre de jour depuis la derniere installation du systeme
# format de date ANNEEMOISJOURHEUREMINUTE
DATE_INSTALLATION_SYSTEME=2016081000
DATE_INSTALLATION_SYSTEME_FICHIER="$BACKUP_REPO/DATE_INSTALLATION_SYSTEME.$DATE_INSTALLATION_SYSTEME"

# --------- Chargement d'une configuration sur le serveur
if [ -e $CUSTOM_CONFIG ]; then
   source $CUSTOM_CONFIG
   echo "Chargement d'une configuration sur le serveur: $CUSTOM_CONFIG"
fi

# ----------------------------------------------------------- #
#       Preparation de l'environnement de travail             #
# ----------------------------------------------------------- #

# --------- Creation du repertoires de sauvegarde
[ ! -d "$CURRENT_WORKING_REPO" ] && "$MKDIR" -p "$CURRENT_WORKING_REPO" || :
# --------- Creation du repertoire temporaire
[ ! -d "$TMP_BACKUP_REPO" ] && "$MKDIR" -p "$TMP_BACKUP_REPO" || :

# --------- Creation du fichier de log
LOG_INFO="$CURRENT_WORKING_REPO/backup_$(date +%Y-%m-%d_%H.%M.%S).log";
echo "[$(date +%F-%T)] - Sur le serveur $HOSTNAME, le repertoire de travail est : " "$CURRENT_WORKING_REPO" > "$LOG_INFO";

# --------- Creation du fichier d'unicite de programme
if [ ! -e $LOCKFILE ]; then
   $TRAP "$RM -f $LOCKFILE; exit" INT TERM EXIT 2> /dev/null
   $TOUCH $LOCKFILE
   echo "[$(date +%F-%T)] - Creation du fichier d'unicite de programme : $LOCKFILE" >> "$LOG_INFO";
else
   echo "[$(date +%F-%T)] - Le programme est deja en cours d'execution car le fichier $LOCKFILE existe" >> "$LOG_INFO";
   echo "[$(date +%F-%T)] - Le programme est deja en cours d'execution car le fichier $LOCKFILE existe" ;
   echo "[$(date +%F-%T)] - Fin du traitement" >> "$LOG_INFO";
   exit 1
fi

# --------- Verification de l'existence des programmes sur le serveur

COMMANDES_NECESSAIRES="$GZIP $MKDIR $RSYNC $SSH $MAIL $TAR $TOUCH $RM $TRAP $HOSTNAME"
COMMANDES_MANQUANTES=0
for COMMANDE_NECESSAIRE in "$COMMANDES_NECESSAIRES"; do
  if ! hash "$COMMANDE_NECESSAIRE" >/dev/null 2>&1; then
    printf "Command not found in PATH: %s\n" "$COMMANDE_NECESSAIRE" >&2
    echo "***************************************************************************" >> "$LOG_INFO";
    echo "[$(date +%F-%T)] - Erreur, le programme $COMMANDE_NECESSAIRE est necessaire" >> "$LOG_INFO";
    ((COMMANDES_MANQUANTES++))
  fi
done

if (($COMMANDES_MANQUANTES > 0)); then
  echo "***********************************************************************************" >> "$LOG_INFO";
  echo "[$(date +%F-%T)] - Erreur, plusieurs programmes manquent pour l'execution du script" >> "$LOG_INFO";
  echo "[$(date +%F-%T)] - Fin du traitement" >> "$LOG_INFO";
  exit 1
fi

# ----------------------------------------------------------- #
#        Sauvegarde de la liste des packages installes        #
# ----------------------------------------------------------- #

echo "[$(date +%F-%T)] - Lancement de dpkg selection" >> "$LOG_INFO";
$DPKG --get-selections | $GZIP -f -9  > "$CURRENT_WORKING_REPO/dpkg_--get-selections.$DATE_NOW.txt.gz";
if [ ! $? -eq 0 ] ; then
  echo "[$(date +%F-%T)] - Une erreur s'est produite lors de la sauvegarde de la liste des packages installes " >> "$LOG_INFO";
fi


# ----------------------------------------------------------- #
#        Sauvegarde de la liste des configuration modifiés    #
# ----------------------------------------------------------- #

echo "[$(date +%F-%T)] - Lancement de la sauvegarde des fichiers de configuration modifiés" >> "$LOG_INFO";

# creation du fichier de reference pour la date d'installation du systeme
[ ! -d "$DATE_INSTALLATION_SYSTEME_FICHIER" ] && "$TOUCH" -t "$DATE_INSTALLATION_SYSTEME" "$DATE_INSTALLATION_SYSTEME_FICHIER" || :

"$FIND" /etc -cnewer "$DATE_INSTALLATION_SYSTEME_FICHIER" -type f -exec cp --parents '{}' "$TMP_BACKUP_REPO" \;
if [ ! $? -eq 0 ] ; then
  echo "[$(date +%F-%T)] - Une erreur s'est produite lors de la sauvegarde des fichiers de configuration modifiés" >> "$LOG_INFO";
else
  $TAR czf "$CURRENT_WORKING_REPO/etc_modif_$DATE_NOW.tar.gz" "$TMP_BACKUP_REPO";
  if [ ! $? -eq 0 ] ; then
        echo "[$(date +%F-%T)] - Une erreur s'est produite lors de la sauvegarde des fichiers de configuration modifiés" >> "$LOG_INFO";
  else
        $RM -rf "$TMP_BACKUP_REPO"
  fi
fi

# ----------------------------------------------------------- #
#        Lancement du sauvegarde des repertoires              #
# ----------------------------------------------------------- #


echo "[$(date +%F-%T)] - Lancement du backup des sites" >> "$LOG_INFO";

for REPO in $LISTE_REPO_A_SAUVEGARDER
do
   NOM_REPO=$(basename $REPO);
   echo "[$(date +%F-%T)] - Traitement du repertoire $NOM_REPO pour $REPO" >> "$LOG_INFO";
   NBR_FICHIER_MODIFIER_HIER=$($FIND $REPO -type f -mmin -1440 -exec ls -l {} \; | grep -v '/web/global' | wc -l);
   if [ ! $NBR_FICHIER_MODIFIER_HIER -eq 0 ] ; then
   	echo "[$(date +%F-%T)] - Creation d'un nouveau fichier " >> "$LOG_INFO";

	# liste des differences entre version
        $FIND $REPO -type f -mmin -1440 -exec ls -l {} \; | grep -v '/web/global' ; >> "$LOG_INFO";
	# liste des fichiers modifies to file
   	#$TAR czf "$CURRENT_WORKING_REPO/$NOM_REPO.$DATE_NOW.tar.gz" "$REPO";
	$MKDIR -p "$BACKUP_REPO/$NOM_REPO/";
	$TAR --create --file="$BACKUP_REPO/$NOM_REPO/$NOM_REPO.INC.$DATE_NOW.tar.gz" --listed-incremental="$BACKUP_REPO/$NOM_REPO/$NOM_REPO.tar.listed.incremental_20160809.list" "$REPO";
	# tar --listed-incremental=/dev/null -xvf backup.tar.gz
  else
	echo "[$(date +%F-%T)] - Pas de modification pour le repertoire $REPO" >> "$LOG_INFO";
  fi
done
if [ ! $? -eq 0 ] ; then
  echo "[$(date +%F-%T)] - Une erreur s'est produite lors du lancement du backup des sites" >> "$LOG_INFO";
fi

echo "[$(date +%F-%T)] - Creation d'un fichier de checksum pour les sites" >> "$LOG_INFO";
$MD5SUM "$CURRENT_WORKING_REPO"/*.gz > "$CURRENT_WORKING_REPO/backup.checksum.md5";


# ----------------------------------------------------------- #
#        Mise a jour des droits des fichiers                  #
# ----------------------------------------------------------- #

echo "[$(date +%F-%T)] - mise a jour des droits des fichiers" >> "$LOG_INFO";
chown -R $LOCAL_USER:$LOCAL_GROUP $BACKUP_REPO $BACKUP_REPO_TMP;
chmod -R 770 $BACKUP_REPO $BACKUP_REPO_TMP;

# ----------------------------------------------------------- #
#        Vidage des repertoires /tmp du systeme               #
# ----------------------------------------------------------- #

echo "[$(date +%F-%T)] - Suppression des fichiers de plus de 30 jours des repertoires tmp des utilisateurs" >> "$LOG_INFO";
"$FIND" /home/*/tmp/ -type f -atime +30 -exec $RM {} \;
if [ ! $? -eq 0 ] ; then
  echo "[$(date +%F-%T)] - Une erreur s'est produite lors du la suppression des fichiers de plus de 30 jours des repertoires tmp des utilisateurs" >> "$LOG_INFO";
fi 

echo "[$(date +%F-%T)] - Suppression des fichiers de plus de 50 jours du repertoire de cache" >> "$LOG_INFO";
"$FIND" /var/tmp/ -type f -atime +50 -exec $RM {} \;
if [ ! $? -eq 0 ] ; then
  echo "***************************************************************************************************************************" >> "$LOG_INFO";
  echo "[$(date +%F-%T)] - Une erreur s'est produite lors du la suppression des fichiers de plus de 50 jours du repertoire de cache" >> "$LOG_INFO";                         
fi 

# ----------------------------------------------------------- #
#        Mise a jour des paquetages et firmware               #
# ----------------------------------------------------------- #

echo "[$(date +%F-%T)] - Mise a jour des paquetages" >> "$LOG_INFO";
aptitude update;
aptitude -sy safe-upgrade >> "$LOG_INFO";
rpi-update >> "$LOG_INFO";
df -h  >> "$LOG_INFO";

# ----------------------------------------------------------- #
#        Test du montage du disque usb                           #
# ----------------------------------------------------------- #

ls -l /media/$LOCAL_USER/hddusb  >> "$LOG_INFO";

# ----------------------------------------------------------- #
#        Temperature                                          #
# ----------------------------------------------------------- #

cpuTemp0=$(cat /sys/class/thermal/thermal_zone0/temp)
cpuTemp1=$(($cpuTemp0/1000))
cpuTemp2=$(($cpuTemp0/100))
cpuTempM=$(($cpuTemp2 % $cpuTemp1))
GPU=`/opt/vc/bin/vcgencmd measure_temp`
RAPPORT_TEMP=$(echo CPU temp "=" $cpuTemp1"."$cpuTempM"'C   ---  " GPU $GPU)
echo $RAPPORT_TEMP >> "$LOG_INFO";

# ----------------------------------------------------------- #
#        Fin du traitement de la maintenance                  #
# ----------------------------------------------------------- #

# --------- Suppression du fichier d'unicite de programme
if [ -e $LOCKFILE ]; then
   $RM $LOCKFILE
#   $TRAP - INT TERM EXIT
   echo "[$(date +%F-%T)] - Suppression du fichier d'unicite de programme" >> "$LOG_INFO";
fi

echo "[$(date +%F-%T)] - Fin du traitement" >> "$LOG_INFO";

# ----------------------------------------------------------- #
#        Envoi d'un mail recapitulatif (desactivable)         #
# ----------------------------------------------------------- #

if [ "$NOTIFICATION_MAIL_IS_ACTIVE" = "yes" ] ; then
  $MAIL -s "$NOTIFICATION_MAIL_SUJET $RAPPORT_TEMP" "$NOTIFICATION_MAIL_ADRESSES" < "$LOG_INFO";
  if [ ! $? -eq 0 ] ; then
    echo "[$(date +%F-%T)] - Erreur d'envoi du mail" >> "$LOG_INFO";
  else
    echo "[$(date +%F-%T)] - Envoi du mail OK" >> "$LOG_INFO";
  fi
fi

echo "$LOG_INFO";
exit 0;