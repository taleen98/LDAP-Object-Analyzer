#!/bin/bash

# ANSI color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m' # Reset color to default

figlet -f slant "LDAP ENUM" | lolcat
echo -e "          by t00n${RESET}" | lolcat
echo 
echo -e "${BLUE}Blue is for Users.${RESET}"
echo -e "${CYAN}Cyan is for found Groups.${RESET}"
echo -e "${RED}Red is for Domain Groups.${RESET}"
echo -e "${YELLOW}Yellow is for Local Groups.${RESET}"
echo
echo -n "Your 1st Part Of Your Domain Name: "; read dc1
echo -n "Your 2nd Part Of Your Domain Name: "; read dc2
echo -n "Your Domain Controller IP: "; read DCIP

ldap_result=$(ldapsearch -x -b "DC=$dc1,DC=$dc2" -H ldap://$DCIP)

echo -e "${GREEN}LDAP Search Results:${RESET}"
echo "$ldap_result" | awk -v BLUE="${BLUE}" -v CYAN="${CYAN}" -v RESET="${RESET}" '
    BEGIN {
        RS="\n\n"  # Set the record separator to blank lines
        FS="\n"     # Set the field separator to newline
        isUser = 0
        isGroup = 0
        sAMAccountName = ""
        dn = ""
    }
    {
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^objectClass: (person|organizationalPerson|user)/) {
                isUser = 1
                isGroup = 0
            }
            if ($i ~ /^objectClass: (group|groupOfNames)/) {
                isGroup = 1
                isUser = 0
            }
            if ($i ~ /^sAMAccountName:/) {
                sub(/^sAMAccountName: /, "", $i)  # Remove the attribute name
                sAMAccountName = $i
            }
            if ($i ~ /^dn:/) {
                sub(/^dn: /, "", $i)  # Remove the attribute name
                dn = $i
            }
        }
        if (isUser == 1) {
            print BLUE "This object is a user:" RESET
            print BLUE "sAMAccountName: " sAMAccountName RESET
            print sAMAccountName > "Users.txt"
            isUser = 0
            sAMAccountName = ""
        } else if (isGroup == 1) {
            print CYAN "This object is a group:" RESET
            print CYAN "sAMAccountName: " sAMAccountName RESET
            isGroup = 0
            if (dn != "") {
                print dn > "DNs.txt"
            }
            dn = ""
        }
        print "---"  # Separating line between objects
    }
'

# Sort the file DNs.txt from repetition
sort -u -o "DNs.txt" "DNs.txt"

# Collect descriptions with sAMAccountName in a file called Description.txt
> Description.txt  # Clear the file before appending
ldapsearch -H ldap://$DCIP -x -b "DC=$dc1,DC=$dc2" "(objectClass=*)" sAMAccountName description | awk '
    BEGIN {
        sAMAccountName = "";
        description = "";
    }
    /^sAMAccountName:/ { sAMAccountName = $2; }
    /^description:/ { description = $2; }
    /^$/ {
        if (sAMAccountName && description) {
            print "sAMAccountName: " sAMAccountName ", description: " description;
        }
        sAMAccountName = "";  # Reset for the next entry
        description = "";     # Reset for the next entry
    }
' >> Description.txt

# Now, iterate through DNs in DNs.txt and check groupType
> DomainGroups.txt  # Create or clear DomainGroups.txt
> LocalGroups.txt   # Create or clear LocalGroups.txt

while IFS= read -r dn; do
    groupType_result=$(ldapsearch -x -b "$dn" -H ldap://$DCIP -s base groupType)
    if [[ "$groupType_result" == *"groupType: -2147483640"* || "$groupType_result" == *"groupType: -2147483646"* ]]; then
        # Print the sAMAccountName of Domain Group
        sAMAccountName=$(ldapsearch -x -b "$dn" -H ldap://$DCIP -s base sAMAccountName | awk '/sAMAccountName:/{print}')
        echo -e "${GREEN}This group is a Domain Group:${RESET} ${YELLOW}$sAMAccountName${RESET}"
        echo "$sAMAccountName" >> DomainGroups.txt
    elif [[ "$groupType_result" == *"groupType: -2147483644"* ]]; then
        # Print the sAMAccountName of Local Group
        sAMAccountName=$(ldapsearch -x -b "$dn" -H ldap://$DCIP -s base sAMAccountName | awk '/sAMAccountName:/{print}')
        echo -e "${GREEN}This group is a Local Group:${RESET} ${RED}$sAMAccountName${RESET}"
        echo "$sAMAccountName" >> LocalGroups.txt
    else
        echo -e "${RED}Error: Unable to determine the group type for DN: $dn${RESET}"
    fi
done < "DNs.txt"

echo 
echo -e "${GREEN}All Found Usernames Have Been Saved To File${RESET} ${BOLD_GREEN} Users.txt${RESET}"
echo -e "${GREEN}All Found Users' Descriptions Have Been Saved To File${RESET} ${BOLD_GREEN} Description.txt${RESET}"
echo -e "${GREEN}All Domain Groups Have Been Saved To File${RESET} ${BOLD_GREEN} DomainGroups.txt${RESET}"
echo -e "${GREEN}All Local Groups Have Been Saved To File${RESET} ${BOLD_GREEN} LocalGroups.txt${RESET}"
