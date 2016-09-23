#!/bin/bash
# Script de backup quotidien d'un serveur Debian
#     Backup du serveur MySQL databases (Dump toutes les bases et les compresses en tar.gz)
#     Backup de repertoires
#     Backup de la liste des packages installes
#     Vidage des repertoires /tmp du systeme
#     Synchronisation des fichiers vers le serveur distant
#     Envoi d'un mail recapitulatif (desactivable)
#
# Written by Fabwice
# http://gwadanina.net

# ----------------------------------------------------------- #
#       Gestion des parametres de configuration               #
# ----------------------------------------------------------- #

# --------- Parametres du systeme
MYSQL="$(which mysql)"
MYSQLDUMP="$(which mysqldump)"
GZIP="$(which gzip)"
MKDIR="$(which mkdir)"
MYSQLCHECK="$(which mysqlcheck)"
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
CURRENT_WORKING_REPO_SQL="$CURRENT_WORKING_REPO/mysql"
TMP_BACKUP_REPO="$BACKUP_REPO_TMP/backup_etc_modif_$DATE_NOW";
LOCKFILE="$CURRENT_WORKING_REPO/.lockfile"

# fichier de configuration local
CUSTOM_CONFIG="/etc/maintenance-service.cfg"

# --------- Configuration du serveur de backup distant
REMOTE_USER="archivekb"
REMOTE_HOST="gwadanina.net_"
REMOTE_PORT=22
REMOTE_PATH="/home/$REMOTE_USER/backupdir"
REMOTE_PATH_FIN_DE_TRANSFERT="$REMOTE_PATH/BACKUP/$ANNEE_MOIS_NOW/$DATE_NOW/FIN_DE_TRANSFERT"

# ----------- Fichier de log de travail
LOG_INFO="$CURRENT_WORKING_REPO/backup_$DATE_NOW.log"

# -----------  Configuration de la conservation des fichiers
CONSERVATION_FICHIER_IS_ACTIVE="yes"
NBR_JOURS_CONSERVATION=90
REPOSITORY_CHMOD="770"
LISTE_REPO_A_SAUVEGARDER="/etc/ /home/web/"

# --------- Configuration du serveur MySQL en local
SQL_LOCAL_USER="sqluser"
SQL_LOCAL_PASSWORD="sqlpassword"
SQL_LOCAL_SERVER_HOST="localhost"

# Database a ne pas sauvegarder (a separer par des espaces)
DATABASE_A_NE_PAS_SAUVEGARDER="information_schema"

# --------- Configuration des Mails de notifications
NOTIFICATION_MAIL_IS_ACTIVE="yes"
NOTIFICATION_MAIL_ADRESSES="backup@gwadanina.net_"
NOTIFICATION_MAIL_SUJET="[BACKUP-$HOSTNAME]"

# --------- Nombre de jour depuis la derniere installation du systeme
# format de date ANNEEMOISJOURHEUREMINUTE
DATE_INSTALLATION_SYSTEME=201511031000
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
# --------- Creation du repertoires de sauvegarde sql
[ ! -d "$CURRENT_WORKING_REPO_SQL" ] && "$MKDIR" -p "$CURRENT_WORKING_REPO_SQL" || :
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

COMMANDES_NECESSAIRES="$MYSQL $MYSQLDUMP $GZIP $MKDIR $MYSQLCHECK $RSYNC $SSH $MAIL $TAR $TOUCH $RM $TRAP $HOSTNAME"
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
#       Lancement de la sauvegarde de la base de donnees      #
# ----------------------------------------------------------- #

echo "[$(date +%F-%T)] - Creation de la liste de toutes les bases de données" >> "$LOG_INFO";
LISTE_BASE_DONNEES="$($MYSQL -u$SQL_LOCAL_USER -h$SQL_LOCAL_SERVER_HOST -p$SQL_LOCAL_PASSWORD -Bse 'show databases')";

if [ ! $? -eq 0 ] ; then
    echo "[$(date +%F-%T)] - Une erreur s'est produite lors de la creation de la liste des bases de données " >> "$LOG_INFO";
fi

echo "[$(date +%F-%T)] - Liste des bases de donnees : $LISTE_BASE_DONNEES" >> "$LOG_INFO";

for BASE in $LISTE_BASE_DONNEES
do
    # analyse et verification des tables
    if [ "$BASE" != "boutique" ] ; then
    $MYSQLCHECK -u$SQL_LOCAL_USER -h$SQL_LOCAL_SERVER_HOST -p$SQL_LOCAL_PASSWORD --auto-repair  --optimize  "$BASE";
    if [ ! $? -eq 0 ] ; then
        echo "[$(date +%F-%T)] - Une erreur s'est produite lors de l'analyse ou la verification de la table " "$BASE" "" >> "$LOG_INFO";
    fi
    fi
    skipdb=-1
    if [ "$DATABASE_A_NE_PAS_SAUVEGARDER" != "" ] ; then
        for i in $DATABASE_A_NE_PAS_SAUVEGARDER
        do
            [ "$BASE" == "$i" ] && skipdb=1 && echo "[$(date +%F-%T)] - Pas de backup pour la base $BASE" >> "$LOG_INFO" || :
        done
    fi

    # Creation des dumps de la base
    if [ "$skipdb" == "-1" ] ; then
        echo "[$(date +%F-%T)] - Dump de la base $BASE" >> "$LOG_INFO";
        SQL_FILE_NAME="$CURRENT_WORKING_REPO_SQL/$BASE.$DATE_NOW.sql.gz";
        $MYSQLDUMP -u$SQL_LOCAL_USER -h$SQL_LOCAL_SERVER_HOST -p$SQL_LOCAL_PASSWORD $BASE | $GZIP -f -9 > "$SQL_FILE_NAME";
        if [ ! $? -eq 0 ] ; then
            echo "[$(date +%F-%T)] - An error occurred in backing up " "$BASE" "tables." >> "$LOG_INFO";
        else
            # taille de l'archive
            FILESIZE=`ls -lh $SQL_FILE_NAME | awk '{print $5}'`
            echo "[$(date +%F-%T)] - Creation de l'archive : $SQL_FILE_NAME ($FILESIZE)" >> "$LOG_INFO";
        fi
    fi
done

echo "[$(date +%F-%T)] - Creation d'un fichier de checksum pour les bases de donnees" >> "$LOG_INFO";
$MD5SUM "$CURRENT_WORKING_REPO_SQL"/*.sql.gz > "$CURRENT_WORKING_REPO_SQL/sql.checksum.md5";

$TAR czf "$CURRENT_WORKING_REPO_SQL".tar.gz "$CURRENT_WORKING_REPO_SQL"/;
echo "[$(date +%F-%T)] - Suppression du repertoire de bases de donnees" >> "$LOG_INFO";
rm -rf "$CURRENT_WORKING_REPO_SQL";

$TAR czf "$CURRENT_WORKING_REPO_SQL".var.lib.mysql.tar.gz /var/lib/mysql >> "$LOG_INFO";

# ----------------------------------------------------------- #
#        Suppression des anciens fichiers d'archive           #
# ----------------------------------------------------------- #

if [ "$CONSERVATION_FICHIER_IS_ACTIVE" = "yes" ] ; then
    echo "[$(date +%F-%T)] - Recherche et supprime les archives de plus $NBR_JOURS_CONSERVATION jours" >> "$LOG_INFO";
    "$FIND" "$BACKUP_REPO" -maxdepth 1 -type f -ctime +$NBR_JOURS_CONSERVATION  -exec $RM -v {} \;
    if [ ! $? -eq 0 ] ; then
        echo "[$(date +%F-%T)] - Une erreur s'est produite lors de la recherche et suppression des anciennes archives" >> "$LOG_INFO";
    fi
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
#        Lancement du backup des repertoires                  #
# ----------------------------------------------------------- #


echo "[$(date +%F-%T)] - Lancement du backup des sites" >> "$LOG_INFO";

for REPO in $LISTE_REPO_A_SAUVEGARDER
do
   NOM_REPO=$(basename $REPO);
   echo "[$(date +%F-%T)] - Traitement du repertoire $NOM_REPO pour $REPO" >> "$LOG_INFO";
   NBR_FICHIER_MODIFIER_HIER=$($FIND $REPO -type f -mmin -1440 -exec ls -l {} \; | grep -v '/wp-content/cache/' | grep -v '/web/_data/' | wc -l);
   if [ ! $NBR_FICHIER_MODIFIER_HIER -eq 0 ] ; then
   	echo "[$(date +%F-%T)] - Creation d'un nouveau fichier " >> "$LOG_INFO";

	# liste des differences entre version
        $FIND $REPO -type f -mmin -1440 -exec ls -l {} \; | grep -v '/wp-content/cache/' | grep -v '/web/_data/' | grep -v '/web/global' ; >> "$LOG_INFO";
	# liste des fichiers modifies to file
   	#$TAR czf "$CURRENT_WORKING_REPO/$NOM_REPO.$DATE_NOW.tar.gz" "$REPO";
	$MKDIR -p "$BACKUP_REPO/$NOM_REPO/";
	$TAR --create --file="$BACKUP_REPO/$NOM_REPO/$NOM_REPO.INC.$DATE_NOW.tar.gz" --listed-incremental="$BACKUP_REPO/$NOM_REPO/$NOM_REPO.tar.listed.incremental_20160412.list" "$REPO";
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
#        Synchronisation des fichiers vers le serveur distant #
# ----------------------------------------------------------- #

echo "[$(date +%F-%T)] - debut de de synchronisation vers le serveur $REMOTE_HOST" >> "$LOG_INFO";
echo su - "$LOCAL_USER" -c "$RSYNC -azv -e '$SSH -p $REMOTE_PORT' $BACKUP_REPO $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH" >> "$LOG_INFO";
su - "$LOCAL_USER" -c "$RSYNC -azv -e '$SSH -p $REMOTE_PORT' $BACKUP_REPO $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH";
if [ ! $? -eq 0 ] ; then
  echo "*************************************************************************" >> "$LOG_INFO";
  echo "[$(date +%F-%T)] - Erreur de synchronisation vers le serveur $REMOTE_HOST" >> "$LOG_INFO";
fi 

# --------- Envoi d'un fichier vide de fin de transfert
su - "$LOCAL_USER" -c "$SSH -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST '$TOUCH_REMOTE $REMOTE_PATH_FIN_DE_TRANSFERT'" >> "$LOG_INFO";
if [ ! $? -eq 0 ] ; then
  echo "***********************************************************************" >> "$LOG_INFO";
  echo "[$(date +%F-%T)] - Erreur d'envoi d'un fichier vide de fin de transfert" >> "$LOG_INFO";
fi 


# --------- Retourne la liste des nouveaux fichiers sur le serveur distant depuis 24 heures
echo "[$(date +%F-%T)] - liste des nouveaux fichiers" >> "$LOG_INFO";
su - "$LOCAL_USER" -c "$SSH -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST '$FIND $REMOTE_PATH/ -type f -mmin -1440 -exec ls -l {} \; | sort -k7 '" | awk '{print $5, $8, $9}' >> "$LOG_INFO";
if [ ! $? -eq 0 ] ; then
  echo "[$(date +%F-%T)] - Erreur lors du retour de la liste des nouveaux fichiers sur le serveur distant depuis 24 heures" >> "$LOG_INFO";
fi 

# ----------------------------------------------------------- #
#        Vidage des repertoires /tmp du systeme               #
# ----------------------------------------------------------- #

#echo "[$(date +%F-%T)] - Suppression des fichiers cree par apache de plus de 30 jours du repertoire /tmp" >> "$LOG_INFO";
#"$FIND" /tmp/sess_* -type f -atime +30 -user www-data -exec $RM {} \;
#if [ ! $? -eq 0 ] ; then
#  echo "*************************************************************************************************************************************" >> "$LOG_INFO";
#  echo "[$(date +%F-%T)] - Une erreur s'est produite lors du la suppression des fichiers cree par apache de plus de 30 jours du repertoire /tmp" >> "$LOG_INFO";
#fi 

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
#        Mise a jour des paquetages                           #
# ----------------------------------------------------------- #

echo "[$(date +%F-%T)] - Mise a jour des paquetages" >> "$LOG_INFO";
aptitude update;
aptitude -s safe-upgrade >> "$LOG_INFO";

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
  $MAIL -s "$NOTIFICATION_MAIL_SUJET" "$NOTIFICATION_MAIL_ADRESSES" < "$LOG_INFO";
  if [ ! $? -eq 0 ] ; then
    echo "[$(date +%F-%T)] - Erreur d'envoi du mail" >> "$LOG_INFO";
  else
    echo "[$(date +%F-%T)] - Envoi du mail OK" >> "$LOG_INFO";
  fi
fi

echo "$LOG_INFO";
exit 0;
