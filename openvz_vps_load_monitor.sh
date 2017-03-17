#-----############

# Script for OpenVZ host server/node to check OpenVZ VPSs load averages and remove VPS IP if load average too high
# if load average wont go down VPS will be restarted. Some logs should be added into /root/vmsloadprocesses/

# set email address where reports will be sent
adminmail=YOUR@E-MAILHERE

# set maximum VPS load average in whole numbers (20,55,99), if reached, VPS IP will be removed
maxload=20

# load average acceptable for re-adding VPS IP back
maxload2=4

# Number of load checks. One check per 5 seconds. If check number exceeded and load is still high after removing IP, we restart the VPS. 24x5=120seconds
looptimes=40

# number of seconds delay between load average checks (multiply this value by $looptimes and we have time in seconds to give VPS to decrease its load before we restart it)
loopsec=5

# a few lines down replace OpenVZ VPS IDs 860, 9999, 111590 by ones that you never want restarted/nullrouted

# --------------------------------------

for ctid in $(/usr/sbin/vzlist -Ho ctid);do
# whitelist some VPS to never be suspended
if [ "$ctid" == "860" ] || [ "$ctid" == "9999" ] || [ "$ctid" == "111590" ];then
continue
fi

# get load average for a CTID
vmload=$(/usr/sbin/vzlist -Ho ctid,laverage | grep $ctid | awk '{print $2}' | cut -c-5 | tr -d /)
# round load average to whole number
vmload=$(printf "%.0f" $vmload)

# if vm load is higher tha $maxload, do action
if [ "$vmload" -gt "$maxload" ];then

echo "$ctid load is higher than $maxload, its BAD.. lets do some action with that VPS.."

# get that VPS IP
vmip=$(/usr/sbin/vzlist -Ho ctid,ip | grep $ctid | awk '{print $2}')

# If VPS IP is zero, we assume another vmsuspender script is working with VPS, we quit
if [ "$vmip" == "" ];then
result="VPS $ctid do not have IP, but its load is high: $vmload. Maybe some other vmsuspender script removed its IP and working on VPS now. Lets continue to check load average of next VM.."
echo "$result"
echo "$result" | mail -s "$(hostname): $ctid has high load, no IP" $adminmail
echo "Ending this FOR loop and continuing with next VPS.."
continue
fi

# mail overloaded VPS process list to admin to see what is going on
#vzctl exec $ctid ps auxf | mail -s "$(hostname) VPS $ctid process list during high load" $adminmail
mkdir /root/vmsloadprocesses
mkdir /root/vmsloadprocesses/$ctid
/usr/sbin/vzctl exec $ctid ps auxf > /root/vmsloadprocesses/$ctid/high_load_processes
/usr/sbin/vzctl exec $ctid free -m >> /root/vmsloadprocesses/$ctid/high_load_processes
/usr/sbin/vzctl exec $ctid top -cn1 >> /root/vmsloadprocesses/$ctid/high_load_processes
/usr/sbin/vzctl exec $ctid netstat -plan |grep :80|awk '{print $5}' |cut -d: -f1 |sort |uniq -c |sort -n >> /root/vmsloadprocesses/$ctid/high_load_processes

echo "Deleting VPS IP $vmip ..."
/usr/sbin/vzctl set $ctid --ipdel $vmip
#vzctl exec $ctid restart httpd
#vzctl exec $ctid service httpd restart


# After removing VPS IP, lets wait until its load average goes down
loopnumber=1
while [ "$vmload" -gt "$maxload2" ];do

loopnumber=$((loopnumber+1))
sleep 5

# getting current load average
vmload=$(/usr/sbin/vzlist -Ho ctid,laverage | grep $ctid | awk '{print $2}' | cut -c-5 | tr -d /)
vmload=$(printf "%.0f" $vmload)
echo "Sleeping until VPS $ctid load goes under $maxload2. Currently: $vmload. This is check number $(($loopnumber - 1))/$looptimes"

# restart VPS if looped maximum allowed times
if [ "$loopnumber" -gt "$looptimes" ];then
echo "Load average $vmload is still too high \(above maxload2: $maxload2\), even after $(($looptimes * $loopsec)) seconds of removing VM IP $vmip. So lets restart VM to clear processes."
echo "Killing any process containing vmid, so restart succeed (malicious finder can be hanging vps):"
pkill -f "/vz/root/$ctid/"
echo "Check if VPS restart command outputted exited with status 7, if yes, kill vm checkpoint also:"
vmrestartt=$(/usr/sbin/vzctl restart $ctid)
if [[ "$vmrestartt" == *"exited with status 7"* ]];then
/usr/sbin/vzctl chkpnt $ctid --kill
sleep 10
/usr/sbin/vzctl --verbose restart $ctid
fi
echo "vmsuspender script at $(hostname) runs as a cronjob and it had to restart VPS $ctid.

This VPS load average was higher than $maxload and even the VPS restarter/IP nuller script removed VPS IP $vmip for $(($looptimes * $loopsec)) seconds, load average did not decreased under $maxload2 . $(cat /root/vmsloadprocesses/$ctid/high_load_processes)" | mail -s "$(hostname): VPS $ctid was auto restarted" $adminmail
break
fi

# Load checking loop before re-adding IP finished
done

echo "$ctid load is probably at acceptable value, lets add IP again"

echo "Adding VPS IP $vmip"
/usr/sbin/vzctl set $ctid --ipadd $vmip --save

# end of VPS high load issue
fi

# end of one VPS load check
done
