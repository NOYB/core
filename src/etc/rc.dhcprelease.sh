#!/bin/sh

# Information resources
# https://tools.ietf.org/html/rfc2132
# https://tools.ietf.org/html/rfc4361
# https://tools.ietf.org/html/rfc3315

# TODO
#
# 1) Client Identifier Acquisition
# Add support for type 255, IAID+DUID.  Depending on how type 255 is implemented it may already be supported via the dhcp-client-identifier option in conf file.
# Find a better source and way of obtaining detecting/finding an option specified Client Identifier.
# Currently attempting to obtain it from the leases db, but not sure if it gets stored there when the option specified in the lease request.
# If it is not found in the leases db, attempting to obtain from interface config file instead.
# If not found in either of those locations attempt to use the hardware type and address.
#
# 2) Hardware Type Acquisition.
# Currently hard coded to 1 (Ethernet).
Hardware_Type='01'	# 2 nibble hex
#
# 3) Hardware Address Acquisition
# For types other than Ethernet.  Currently using MAC address (ether) from ifconfig.
#
# 4) Tests for valid values.  Graceful exit if not.  Partially done.
#
# 5) Code clean up.  Better more robust means of doing things.  Such as, but not exclusive to, obtaining addresses and identifiers from ifconfig, leases file and/or conf file.
#


while getopts dC:L:c:s:o:v:h name
do
	case $name in
	d)	dry_run=1;;
	C)	Cflag=1 Cval="$OPTARG" conf_file="$OPTARG";;
	L)	Lflag=1 Lval="$OPTARG" leases_file="$OPTARG";;
	c)	cflag=1 cval="$OPTARG" Client_Identifier="$OPTARG";;
	s)	sflag=1 sval="$OPTARG" Server_Identifier="$OPTARG";;
	o)	oflag=1 oval="$OPTARG" output="$OPTARG";;
	v)	vflag=1 vval="$OPTARG" verbosity="$OPTARG";;
	h|?)
		printf "Usage: %s: \n\
 [-d] \n\
 [-C conf-file] [-L leases-file] \n\
 [-c dhcp-client-identifier] [-s dhcp-server-identifier] \n\
 [-v verbosity-level] [-o output-type] [-h] interface\n" $0
		printf "\n\
 -d Dry Run - do not send the DHCP release packet. \n\
 -C Configuration file used by DHCP lease request. \n\
 -L Leases database file.  Default: /var/db/dhclient.leases.<interface> \n\
 -c DHCP Client Identifier.  Default: Interface MAC Address \n\
 -s DHCP Server Identifier.  Default: DHCP Server IP Address (from leases db) \n\
 -t Hardware Type.  Default: 1 (Ethernet) \n\
 -o Output type.  'hex' or 'ascii'.  Default: none \n\
 -v Verbosity.  0 to 6.  Default: none \n\
 -h Usage. \n\n"
 		exit 2;;
	esac
done
shift $(($OPTIND - 1))
#printf "Remaining arguments are: %s\n" "$*"


if=$1

if [ ! $Cflag ]; then
	conf_file='/etc/dhclient.conf'				# FreeBSD Default
fi

if [ ! $Lflag ]; then
	leases_file="/var/db/dhclient.leases."$if	# FreeBSD Default
fi

COLEN=":"		# Colen : - Ascii
#COLEN="\\x3A"	# Colen : - Hex

DIGIT="0-9"				# 0-9 - Ascii
#DIGIT="\\x30-\\x39"	# 0-9 - Hex

HEXDIG="A-Fa-f$DIGIT"					# 0-9 or A-F or a-f - Ascii
#HEXDIG="$DIGIT\\x41-\\x46\\x61-\\x66"	# 0-9 or A-F or a-f - Hex

Snum="25[0-5]|2[0-4][0-9]|[01]?[0-9]{1,2}"
IPv4_Address_Literal="($Snum)(\\.($Snum)){3}"

#   IPv6_comp_max_groups="(?=(($COLEN$COLEN)?(([^$COLEN]*)($COLEN|$COLEN$COLEN|(?=\\]))){0,6}\\]))"
#IPv6v4_comp_max_groups="(?=(($COLEN$COLEN)?(([^$COLEN]*)($COLEN|$COLEN$COLEN)){0,4}$IPv4_Address_Literal\\]))"
  IPv6_comp_max_groups=""
IPv6v4_comp_max_groups=""

IPv6_hex="[$HEXDIG]{1,4}"

IPv6_full="$IPv6_hex($COLEN$IPv6_hex){7}"
IPv6_comp="$IPv6_comp_max_groups($IPv6_hex($COLEN$IPv6_hex){0,5})?$COLEN$COLEN($IPv6_hex($COLEN$IPv6_hex){0,5})?"
IPv6v4_full="$IPv6_hex($COLEN$IPv6_hex){5}$COLEN$IPv4_Address_Literal"
IPv6v4_comp="$IPv6v4_comp_max_groups($IPv6_hex($COLEN$IPv6_hex){0,3})?$COLEN$COLEN($IPv6_hex($COLEN$IPv6_hex){0,3}$COLEN)?$IPv4_Address_Literal"

IPv6_addr="$IPv6_full|$IPv6_comp|$IPv6v4_full|$IPv6v4_comp"

#IPv6_Address_Literal="IPv6$COLEN($IPv6_addr)"
IPv6_Address_Literal="($IPv6_addr)"

Snum="[0-9a-fA-F]{2}"
MAC_Address_Literal="($Snum)(\\:($Snum)){5}"

CIDhex="($Snum)(\\:($Snum))+"
CIDstr="[\"\'].*[\"\']"

WS='[ 	]'	# Space or tab.

interface=`ifconfig "$if"`
if [ $? -eq 0 ]; then
      MAC_Address_ifconfig=`printf "%s" "$interface" | grep -m 1 -o -E "ether$WS+$MAC_Address_Literal"      | grep -o -E "$MAC_Address_Literal"`
#     IPv4_Address_ifconfig=`printf "%s" "$interface" | grep -m 1 -o -E "inet$WS+$IPv4_Address_Literal"      | grep -o -E "$IPv4_Address_Literal"`
#     IPv6_Address_ifconfig=`printf "%s" "$interface" | grep -m 1 -o -E "inet6$WS+$IPv6_Address_Literal"     | grep -o -E "$IPv6_Address_Literal"`
#Broadcast_Address_ifconfig=`printf "%s" "$interface" | grep -m 1 -o -E "broadcast$WS+$IPv4_Address_Literal" | grep -o -E "$IPv4_Address_Literal"`
else
	error=$error"Error: Interface not found. ("$if")\n"
fi

# Get the DHCP Lease Record and Pertinent Information from the leases file.
if [ -r "$leases_file" ]; then
	lease_record_line_number=`tail -r "$leases_file" | grep -m 1 -n "lease$WS" | grep -o -E "^[0-9]+"`
	lease_record=`tail -n $lease_record_line_number "$leases_file"`

		 IPv4_Address_leases=`printf "%s" "$lease_record" | grep -m 1 -o -E "fixed-address$WS+$IPv4_Address_Literal"          | grep -o -E "$IPv4_Address_Literal"`
#		 IPv6_Address_leases=`printf "%s" "$lease_record" | grep -m 1 -o -E "fixed-address$WS+$IPv6_Address_Literal"          | grep -o -E "$IPv6_Address_Literal"`
	Server_Identifier_leases=`printf "%s" "$lease_record" | grep -m 1 -o -E "dhcp-server-identifier$WS+$IPv4_Address_Literal" | grep -o -E "$IPv4_Address_Literal"`
	Client_Identifier_leases=`printf "%s" "$lease_record" | grep -m 1 -o -E "dhcp-client-identifier$WS+($CIDhex|$CIDstr);"    | grep -o -E "($CIDhex|$CIDstr)"`
else
	error=$error"Error: DHCP leases file not accessible. ("$leases_file")\n"
fi

# Attempt to get the DHCP Client Identifier from the conf file.
if [ -r "$conf_file" ]; then
	conf=`cat "$conf_file"`
	not_comment='^[^\#]*'

	  Client_Identifier_conf=`printf "%s" "$conf"         | grep -m 1 -o -E "($not_comment)dhcp-client-identifier$WS+($CIDhex|$CIDstr);"    | grep -o -E "($CIDhex|$CIDstr)"`
#else					# For FreeBSD Default
elif [ $Cflag ]; then	# For not using FreeBSD default so optionally specified command line option.
	error=$error"Error: Conf file not accessible. ("$conf_file")\n"
fi

#IP_Address_leases="1234:abc0::5678:def0"
#IP_Address_leases="2b:4d:5e6f:7a8b:9c0d:1e2f:3a4b:5c6d"
#IP_Address_leases="1234:abc0:5678:def0:1234:abc0:1.2.3.4"

if [ $((${#MAC_Address_ifconfig})) -ne 0 ]; then
	MAC_Address=$MAC_Address_ifconfig
fi
if [ $((${#MAC_Address})) -eq 0 ]; then
	error=$error"Error: Client MAC Address, missing.\n"
fi

if [ $((${#IPv4_Address_leases})) -ne 0 ]; then
	IP_Address=$IPv4_Address_leases
#elif [ $((${#IPv4_Address_ifconfig})) -ne 0 ]; then
#	IP_Address=$IPv4_Address_ifconfig
#fi
#elif [ $((${#IPv6_Address_ifconfig})) -ne 0 ]; then
#	IP_Address=$IPv6_Address_ifconfig
fi
if [ $((${#IP_Address})) -eq 0 ]; then
	error=$error"Error: Client IP  Address, missing.\n"
fi

if [ $((${#Broadcast_Address_ifconfig})) -ne 0 ]; then
	Broadcast_Address=$Broadcast_Address_ifconfig
fi
#if [ $((${#Broadcast_Address})) -eq 0 ]; then
#	error=$error"Error: Broadcast Address, missing.\n"
#fi

if [ $sflag ]; then
	Server_Identifier=$sval
elif [ $((${#Server_Identifier_leases})) -ne 0 ]; then
	Server_Identifier=$Server_Identifier_leases
fi
if [ $((${#Server_Identifier})) -eq 0 ]; then
	error=$error"Error:  Server Identifier, missing.\n"
fi

if [ $cflag ]; then
	Client_Identifier=$cval
elif [ $((${#Client_Identifier_leases})) -ne 0 ]; then
	Client_Identifier=$Client_Identifier_leases
elif [ $((${#Client_Identifier_conf})) -ne 0 ]; then
	Client_Identifier=$Client_Identifier_conf
else # Use hardware address and type eg: MAC Address and Ethernet (1)
	Client_Identifier=$Hardware_Type:$MAC_Address
fi
if [ $((${#Client_Identifier})) -eq 0 ]; then
	error=$error"Error:  Client Identifier, missing.\n"
fi


if [ $verbosity ] && [ $verbosity -ge 1 ] || [ $((${#error})) -ne 0 ]; then
	printf "\n"
	printf "Client MAC Address (raw): %s\n" "$MAC_Address"
	printf "Client IP  Address (raw): %s\n" "$IP_Address"
#	printf " Broadcast Address (raw): %s\n" "$Broadcast_Address"
	printf " Server Identifier (raw): %s\n" "$Server_Identifier"
	printf " Client Identifier (raw): %s\n" "$Client_Identifier"
	printf "\n"
	if [ $((${#error})) -ne 0 ]; then
		printf "$error"
		exit 1
	fi
fi



###
#
# Now that all the information has been obtained...
# 1) Convert it to hex.
# 2) Attempt to construct a DHCP release packet.
# 3) Send DHCP release packet.
#
###


# Subroutines

hex2dec(){
	dec=`printf "%s\n" "ibase=16; $1"|bc`
}

dec2hex(){
	hex=`printf "%s\n" "obase=16; $1"|bc`

	# Prepend leading zero (0) if necessary.
	if [ $((${#hex} %2)) -ne 0 ]; then	hex=0$hex
	fi
}

hex2ascii() {
    ascii=''
	for byte in $(printf "%s" "$1" | sed 's/../& /g')
	do
		ascii=$ascii"\\$(printf "%o" 0x$byte)"
	done
}

ascii2hex() {
	hex=`printf "%s" "$1" | hexdump -ve '1/1 "%.2x"'`
}

MACaddr2hex(){
	# Remove octet delimiters (colon, space, dot).
	hex=`printf "%s" "$1" | sed -E 's/[\:\ \.]//g'`
}

# Convert IP address to hex.
IPaddr_dec2hex() {

	# Convert IP address to space delimited octets.
	local IP_Address=`printf "%s" "$1" | sed -E 's/[\.\ \:]/\ /g'`

	# If IPv4... convert decimal address (dot, space, or colon delimited octets) to 4 bytes of 2 nibble hex.
	if [ `printf "%s" "$1" | grep -E "^$IPv4_Address_Literal$"` ]; then
		local octet_length=2

		for octet in $IP_Address
		do
			dec2hex $octet
			local IP_hex_octets=$IP_hex_octets' '$hex
		done

	# If IPv6...
	elif [ `printf "%s" "$1" | grep -E "^$IPv6_Address_Literal$"` ]; then
		local octet_length=4

		for octet in $IP_Address
		do
			local IP_hex_octets=$IP_hex_octets' '$octet
		done

	# Invalid...
	else
		error=$error"Error: Client IP  Address, IPv4 or IPv6 format not met. ("$1")\n"
	fi

	# Prepend leading zero (0) if necessary.
	for octet in $IP_hex_octets
	do
		while [ $((${#octet})) -lt $octet_length ]
		do
			octet=0$octet
		done
		local octets=$octets' '$octet
	done
	local IP_hex_octets=$octets

	# Remove octet delimiters.
	IP_hex=`printf "%s" "$IP_hex_octets" | sed -E 's/[\.\ \:]//g'`
}

# Convert Client Identifier to hex.
CID2hex(){
	# If hex... remove octet delimiters (colon).
	if [ `printf "%s" "$1" | grep -E "^$CIDhex$"` ]; then
		hex=`printf "%s" "$1" | sed -E 's/://g'`

	# If string... remove leading and trailing quotes... convert ascii to hex.
	elif [ `printf "%s" "$1" | grep -E "^$CIDstr$"` ]; then
		str=`printf "%s" "$1" | sed -E 's/^.//' | sed -E 's/.$//'`
		ascii2hex "$str"
	fi
}


# Convert stuff to hex

MACaddr2hex "$MAC_Address"
MACh=$hex
if [ $((${#MACh}/2)) -ne 6 ]; then
	error=$error"Error: Client MAC Address, length (6) not met. ("$((${#MACh}/2))")\n"
fi

IPaddr_dec2hex "$IP_Address"
IPh=$IP_hex
if [ $((${#IPh}/2)) -ne 4 ] && [ $((${#IPh}/2)) -ne 16 ]; then
	error=$error"Error: Client IP  Address, length (4 or 16) not met. ("$((${#IPh}/2))")\n"
fi

IPaddr_dec2hex "$Server_Identifier"
SIh=$IP_hex
if [ $((${#SIh}/2)) -ne 4 ]; then
	error=$error"Error:  Server Identifier, length (4) not met. ("$((${#SIh}/2))")\n"
fi

CID2hex "$Client_Identifier"
CIh=$hex
if [ $((${#CIh}/2)) -lt 2 ]; then
	error=$error"Error:  Client Identifier, minimum length (2) not met. ("$((${#CIh}/2))")\n"
fi


if [ $verbosity ] && [ $verbosity -ge 2 ] || [ $((${#error})) -ne 0 ]; then
	printf "Client MAC Address (hex): %s\n" "$MACh"
	printf "Client IP  Address (hex): %s\n" "$IPh"
	printf " Server Identifier (hex): %s\n" "$SIh"
	printf " Client Identifier (hex): %s\n" "$CIh"
	printf "\n"
	if [ $((${#error})) -ne 0 ]; then
		printf "$error"
		exit 2
	fi
fi



# Calculate and set additional values.

# Set Client Hardware Type (hex)
HTh=$Hardware_Type
if [ $((${#HTh}/2)) -ne 1 ]; then
	error=$error"Error: Client Hardware Type, length (1) not met. ("$((${#HTh}/2))")\n"
fi

# Calculate Client Hardware Address Length (hex)
CHAL=$((${#MACh} / 2))
dec2hex $CHAL; CHALh=$hex
if [ $CHAL -ne 6 ]; then
	error=$error"Error: Client Hardware Address (MAC), length (6) not met. ("$CHAL")\n"
fi

# Generate Random Transaction ID (8 nibble hex)
dec2hex `jot -nr 1 268435456 4294967295`; TIDh=$hex
if [ $((${#TIDh}/2)) -ne 4 ]; then
	error=$error"Error: Transaction ID, length (4) not met. ("$((${#TIDh}/2))")\n"
fi

# Generate Client Hardware Address Padding (hex)
CHAPh=''
while [ $(((${#MACh} + ${#CHAPh})/2)) -lt 16 ]
do
	CHAPh=$CHAPh'00'
done
if [ $(((${#MACh} + ${#CHAPh})/2)) -ne 16 ]; then
	error=$error"Error: Client Hardware Address Length, (16) not met. ("$(((${#MACh} + ${#CHAPh})/2))")\n"
fi

# Calculate Server Identifier Length (hex)
SIL=$((${#SIh} / 2))
dec2hex $SIL; SILh=$hex
if [ $SIL -ne 4 ]; then
	error=$error"Error: Server Identifier Length, (4) not met. ("$SIL")\n"
fi

# Calculate Client Identifier Length (hex)
CIL=$((${#CIh} / 2))
dec2hex $CIL; CILh=$hex
if [ $CIL -lt 2 ]; then
	error=$error"Error: Client Identifier Length, minimum (2) not met. ("$CIL")\n"
fi


if [ $verbosity ] && [ $verbosity -ge 3 ] || [ $((${#error})) -ne 0 ]; then
	printf "                  Hardware Type (hex): %s\n" "$HTh"
	printf "                 Transaction ID (hex): %s\n" "$TIDh"
	printf " Client Hardware Address Length (hex): %s\n" "$CHALh"
	printf "Client Hardware Address Padding (hex): %s\n" "$CHAPh"
	printf "       Server Identifier Length (hex): %s\n" "$SILh"
	printf "       Client Identifier Length (hex): %s\n" "$CILh"
	printf "\n"
	if [ $((${#error})) -ne 0 ]; then
		printf "$error"
		exit 3
	fi
fi



# Set all the fields that go into the packet.

                   Message_Type='01'
                  Hardware_Type=$HTh
        Hardware_Address_Length=$CHALh
                           Hops='00'

                 Transaction_ID=$TIDh
                Seconds_Elapsed='0000'
                    Bootp_Flags='0000'

              Client_IP_Address=$IPh
         Your_Client_IP_Address='00000000'
         Next_Server_IP_Address='00000000'
         Relay_Agent_IP_Address='00000000'

             Client_MAC_Address=$MACh
Client_Hardware_Address_Padding=$CHAPh

     Server_Host_Name_Not_Given='00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'
       Boot_File_Name_Not_Given='0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'

                   Magic_Cookie='63825363'
              DHCP_Message_Type='35''01''07'
          DHCP_Server_Identifer='36'$SILh$SIh
          DHCP_Client_Identifer='3d'$CILh$CIh

                            End='ff'
#                        Padding=''	# Padding is added later.


# Construct Packet (hex)
DHCP_RELEASE=\
$Message_Type\
$Hardware_Type\
$Hardware_Address_Length\
$Hops\
\
$Transaction_ID\
$Seconds_Elapsed\
$Bootp_Flags\
\
$Client_IP_Address\
$Your_Client_IP_Address\
$Next_Server_IP_Address\
$Relay_Agent_IP_Address\
\
$Client_MAC_Address\
$Client_Hardware_Address_Padding\
\
$Server_Host_Name_Not_Given\
$Boot_File_Name_Not_Given\
\
$Magic_Cookie\
$DHCP_Message_Type\
$DHCP_Server_Identifer\
$DHCP_Client_Identifer\
\
$End
#$Padding	# Padding is added later.


# Generate Padding (hex)
Padding=''
while [ $(((${#DHCP_RELEASE} + ${#Padding})/2)) -lt 300 ]
do
	Padding=$Padding'00'
done


# Add padding.
DHCP_RELEASE=$DHCP_RELEASE$Padding
if [ $((${#DHCP_RELEASE}/2)) -ne 300 ]; then
	error=$error"Error: Packet, length (300) not met. ("$((${#DHCP_RELEASE}/2))")\n"
fi


if [ $verbosity ] && [ $verbosity -ge 4 ] || [ $((${#error})) -ne 0 ]; then
	printf "DHCP Release Packet: \n"
	printf "                         Fields  Value (hex)\n"
	printf "                   Message type: %s\n" "$Message_Type"
	printf "                  Hardware type: %s\n" "$Hardware_Type"
	printf "        Hardware address length: %s\n" "$Hardware_Address_Length"
	printf "                           Hops: %s\n" "$Hops"

	printf "                 Transaction ID: %s\n" "$Transaction_ID"
	printf "                Seconds elapsed: %s\n" "$Seconds_Elapsed"
	printf "                    Bootp flags: %s\n" "$Seconds_Elapsed"
	printf "              Client IP address: %s\n" "$Client_IP_Address"

	printf "       Your (client) IP address: %s\n" "$Your_Client_IP_Address"
	printf "         Next server IP address: %s\n" "$Next_Server_IP_Address"
	printf "         Relay agent IP address: %s\n" "$Relay_Agent_IP_Address"

	printf "             Client MAC address: %s\n" "$Client_MAC_Address"
	printf "Client hardware address Padding: %s\n" "$Client_Hardware_Address_Padding"

	printf "     Server host name not given: %s\n" "$Server_Host_Name_Not_Given"
	printf "       Boot file name not given: %s\n" "$Boot_File_Name_Not_Given"

	printf "              DHCP Magic Cookie: %s\n" "$Magic_Cookie"
	printf "              DHCP Message Type: %s\n" "$DHCP_Message_Type"
	printf "         DHCP Server Identifier: %s\n" "$DHCP_Server_Identifer"
	printf "         DHCP Client Identifier: %s\n" "$DHCP_Client_Identifer"

	printf "                            End: %s\n" "$End"
	printf "                        Padding: %s\n" "$Padding"
	printf "\n"
	if [ $((${#error})) -ne 0 ]; then
		printf "$error"
		exit 4
	fi
fi



if [ $verbosity ] && [ $verbosity -ge 5 ] || [ $((${#error})) -ne 0 ]; then
	printf "DHCP Release Packet (hex): \n"
	printf "$DHCP_RELEASE"
	printf "\n\n"
	if [ $((${#error})) -ne 0 ]; then
		printf "$error"
		exit 5
	fi
fi


if [ $output ] && [ $output == "hex" ]; then
	printf "$DHCP_RELEASE"
fi



# Convert packet from hex to ascii
hex2ascii "$DHCP_RELEASE"

if [ $verbosity ] && [ $verbosity -ge 6 ] || [ $((${#error})) -ne 0 ]; then
	printf "DHCP Release Packet (ascii): \n"
	printf "$ascii"
	printf "\n\n"
	if [ $((${#error})) -ne 0 ]; then
		printf "$error"
		exit 6
	fi
fi


if [ $output ] && [ $output == "ascii" ]; then
	printf "$ascii"
fi



#
# Send packet if no errors where detected and not dry run.
#

if [ ! $error ]; then
	Src_Address=$IP_Address
	Src_Port='68'

#	Dst_Address='255.255.255.255'
#	Dst_Address=$Broadcast_Address
	Dst_Address=$Server_Identifier
#	Dst_Address='192.168.2.13'
	Dst_Port='67'

	if [ ! $dry_run ]; then
		printf "$ascii" | nc -4nu -w 0 -s $Src_Address -p $Src_Port $Dst_Address $Dst_Port
		DryRunMsg='sent'
	else
		DryRunMsg='NOT sent'
	fi

	if [ $verbosity ] && [ $verbosity -ge 0 ]; then
		printf "DHCP release packet %s from %s to %s. \n" "$DryRunMsg" "$Src_Address" "$Dst_Address"
	fi
fi
