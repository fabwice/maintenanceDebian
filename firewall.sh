#!/bin/bash                                                                                                                  
### BEGIN INIT INFO                                                                                                                                                                                                                                       
# Provides:          firewall                                                                                                
# Required-Start:    $local_fs                                                                                               
# Required-Stop:     $local_fs                                                                                               
# Default-Start:     S                                                                                                       
# Default-Stop:      0 6                                                                                                     
# Short-Description: firewall                                                                                                
# Description:       firewall 
# Fabwice pour gwadanina.net                                                                                               
### END INIT INFO                                                                                                            
                                                                                                                             
                                                                                                                             
echo "[Setting firewall rules...]"                                                                                           
                                                                                                                             
                                                                                                                             
# Configuration:                                                                                                             
PORTSSH=22                                                                                                                 
                                                                                                                             
# config de base                                                                                                             
# Vider les tables actuelles                                                                                                 
        iptables -t filter -F                                                                                                
        iptables -t filter -X                                                                                                
echo "[Vidage : OK]"                                                                                                         
                                                                                                                             
# Autoriser SSH                                                                                                              
        iptables -t filter -A INPUT -p tcp --dport $PORTSSH -j ACCEPT                                                        
#	iptables -t filter -A INPUT -p tcp -i ! lo --dport 22 -j DROP
echo "[Autoriser SSH : OK]"                                                                                                  
                                                                                                                             
# Ne pas casser les connexions etablies                                                                                      
        iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT                                                     
        iptables -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT                                                    
echo "[Ne pas casser les connexions établies : OK]"                                                                          
                                                                                                                             
# Interdire toute connexion entrante                                                                                         
        iptables -t filter -P INPUT DROP                                                                                     
        iptables -t filter -P FORWARD DROP                                                                                   
echo "[Interdire toute connexion entrante : OK]"                                                                             
                                                                                                                             
# Interdire toute connexion sortante                                                                                         
        iptables -t filter -P OUTPUT DROP                                                                                    
echo "[Interdire toute connexion sortante : OK]"                                                                             
                                                                                                                             
# Autoriser les requetes DNS, FTP, HTTP, NTP (pour les mises a jour)                                                         
        iptables -t filter -A OUTPUT -p tcp --dport 21 -j ACCEPT                                                             
        iptables -t filter -A OUTPUT -p tcp --dport 80 -j ACCEPT                                                             
        iptables -t filter -A OUTPUT -p tcp --dport 25 -j ACCEPT                                                             
        iptables -t filter -A OUTPUT -p udp --dport 25 -j ACCEPT                                                             
        iptables -t filter -A OUTPUT -p udp --dport 53 -j ACCEPT                                                             
        iptables -t filter -A OUTPUT -p tcp --dport 53 -j ACCEPT                                                             
        iptables -t filter -A OUTPUT -p udp --dport 123 -j ACCEPT                                                            
        iptables -t filter -A OUTPUT -p tcp --dport 443 -j ACCEPT                                                            
        iptables -t filter -A OUTPUT -p udp --dport 993 -j ACCEPT                                                            
        iptables -t filter -A OUTPUT -p tcp --dport 993 -j ACCEPT                                                            
        iptables -t filter -A OUTPUT -p udp --dport 465 -j ACCEPT                                                            
        iptables -t filter -A OUTPUT -p tcp --dport 465 -j ACCEPT                                                            
echo "[Autoriser les requetes SMTP, DNS, FTP, HTTP, NTP : OK]"                                                               
                                                                                                                             
# Autoriser loggin sur serena                                                                                                
    iptables -t filter -A OUTPUT -p tcp --dport 2222 -j ACCEPT                                                               
                                                                                                                             
# Autoriser loopback                                                                                                         
        iptables -t filter -A INPUT -i lo -j ACCEPT                                                                          
        iptables -t filter -A OUTPUT -o lo -j ACCEPT                                                                         
        iptables -t filter -A OUTPUT -o lo -s 0.0.0.0/0 -d 0.0.0.0/0 -j ACCEPT                                               
        iptables -t filter -A INPUT  -i lo -s 0.0.0.0/0 -d 0.0.0.0/0 -j ACCEPT                                               
echo "[Autoriser loopback : OK]"                                                                                             
                                                                                                                             
# Autoriser ping                                                                                                             
        iptables -t filter -A INPUT -p icmp -j ACCEPT                                                                        
        iptables -t filter -A OUTPUT -p icmp -j ACCEPT                                                                       
echo "[Autoriser ping : OK]"                                                                                                          
                                                                                                                             
# Syn-Flood                                                                                                                  
        if [ -e /proc/sys/net/ipv4/tcp_syncookies ] ; then                                                                   
            echo 1 > /proc/sys/net/ipv4/tcp_syncookies                                                                       
        fi                                                                                                                   
                                                                                                                             
        iptables -A FORWARD -p tcp --syn -m limit --limit 1/second -j ACCEPT                                                 
        iptables -A FORWARD -p udp -m limit --limit 1/second -j ACCEPT                                                       
echo "[Limiter le Syn-Flood : OK]"                                                                                           
                                                                                                                             
# Spoofing                                                                                                                   
        if [ -e /proc/sys/net/ipv4/conf/all/rp_filter ] ; then                                                               
                 echo 1 > /proc/sys/net/ipv4/conf/all/rp_filter                                                              
                 echo 1 > /proc/sys/net/ipv4/conf/default/rp_filter                                                          
                 echo 1 > /proc/sys/net/ipv4/conf/eth0/rp_filter                                                             
                 echo 1 > /proc/sys/net/ipv4/conf/lo/rp_filter                                                               
        fi                                                                                                                   
                                                                                                                             
        iptables -N SPOOFED                                                                                                  
        iptables -A SPOOFED -s 127.0.0.0/8 -j DROP                                                                           
        iptables -A SPOOFED -s 169.254.0.0/12 -j DROP                                                                        
        iptables -A SPOOFED -s 172.16.0.0/12 -j DROP                                                                         
        iptables -A SPOOFED -s 192.168.0.0/16 -j DROP                                                                        
        iptables -A SPOOFED -s 10.0.0.0/8 -j DROP                                                                            
                                                                                                                             
echo "[Bloquer le Spoofing : OK]"                                                                                            
                                                                                                                             
# Parametrage au niveau du noyau                                                                                             
if [ -e /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts ] ; then                                                              
            echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts                                                          
fi                                                                                                                           
if [ -e /proc/sys/net/ipv4/conf/all/accept_redirects ] ; then                                                                
            echo 0 > /proc/sys/net/ipv4/conf/all/accept_redirects                                                            
fi                                                                                                                           
if [ -e /proc/sys/net/ipv4/conf/all/send_redirects ] ; then                                                                  
            echo 0 > /proc/sys/net/ipv4/conf/all/send_redirects                                                              
fi                                                                                                                           
echo "[Parametrage au niveau du noyau : OK]"
                                                                                                                        
echo Firewall mis a jour avec succes !