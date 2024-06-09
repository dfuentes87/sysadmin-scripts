#!/usr/bin/python3.4
#NiceFileName: Migrate
#FileDescription: Migration Script for Managed Services
import os, re, sys
from distutils.util import strtobool as strtobool
mig_tuple = ('server','shared', 'cPanel', 'Plesk', 'other')

class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def generate(platform, panel, domain, temp, ip, hostsfile, fms, signature):
    '''Outputs an HTML-formatted IRIS reply for migrations. 
    
    Keyword arguments:
    platform -- Hosting type
    panel -- Control panel
    domain -- domain
    ip -- address

    Returns: string
    '''
    # 0 = domain
    # 1 = temp
    # 2 = ip
    # 3 = expert services / managed services
    if fms == 'Expert':
        phone = '(480) 505-8877'
    else:
        phone = '(480) 366-3310'
    email = bcolors.OKBLUE + '''Subject:\n''' + bcolors.FAIL + '''{4} Services - {0}: Migration Complete\n\n''' + bcolors.OKBLUE + '''Message Body:''' + bcolors.FAIL + '''\nDear Sir/Madam,<br /><br />We have completed your migration for <b><em>{0}</em></b>. '''

    hosts = '''You can test it out by editing your hosts file, which we've included the directions for below.<br><br>Below is the line you need to add:<br>--------------------------------------------------------------------------------------<br><small><b>{2} {1} www.{1}<br></b></small>--------------------------------------------------------------------------------------<br><br>Adding entries to your hosts file lets you view the files you uploaded to your hosting account before changing your domain's nameservers. To do this, add your hosting account's IP address as an entry on your computer's&nbsp;<code>hosts</code>&nbsp;file.<br><br>Host files are text documents that you can edit with any text editor. You will simply add the Server IP Address and your domain name to your host file on an individual line. Follow the format of any previous entries for the order of the IP address and domain name.<br><br>Host file paths for popular operating systems:<br><br><small>&bull; &nbsp;Linux:&nbsp;<em>/etc/hosts</em><br>&bull; &nbsp;Macintosh OS X:&nbsp;<em>/etc/hosts</em><br>&bull; &nbsp;Macintosh OS 9: In&nbsp;<em>System Folder&gt;Preferences</em><br>&bull; &nbsp;WindowsXP Home:&nbsp;<em>C:\windows\system32\drivers\etc\hosts</em><br>&bull; &nbsp;Windows NT/2000/XP Pro:&nbsp;<em>c:\winnt\system32\drivers\etc\hosts</em><br>&bull; &nbsp;Windows 95/98/Me:&nbsp;<em>c:\windows\hosts</em><br>&bull; &nbsp;Windows 7/Vista:&nbsp;<em>c:\windows\system32\drivers\etc\hosts</em><br><br></small>--------------------------------------------------------------------------------------<br><small><b>PLEASE NOTE:</b> After your domain propagates be sure to remove the entry from your HOSTS file, as if you change plans or servers in the future, you will not be able to view your site. &nbsp;We do not condone or support modifying your system files, do so at your own risk.<br></small>--------------------------------------------------------------------------------------<br><br>'''

    live = '''Once you are ready to make the switch live, you will just need to point DNS for the domain/subdomain to your destination server. The easiest method is to update your current DNS zone file's A record for <em><b>{0}</b></em> to point to <em><b>{2}</b></em>.<br><br><small>&bull; &nbsp;<a href="http://help.securepaynet.net/article/680">Managing DNS for Your Domain Names</a><br><br></small>'''

    server = '''<small>If you choose, you can also create your own nameservers to point your entire domain's DNS zone file to. &nbsp;For more information, please see: &nbsp;<br><br>&bull; &nbsp;<a href="http://help.securepaynet.net/article/664">Setting Nameservers for Your Domain Names</a><br /></small>'''
    cpanel = '''<small>&bull; &nbsp;<a href="http://help.securepaynet.net/article/8467">Setting up Nameserver DNS Using cPanel/WebHost Manager</small></a><br><br>'''
    plesk = '''<small>&bull; &nbsp;<a href="http://help.securepaynet.net/article/8463/">Setting up Nameserver DNS Using Parallels Plesk Panel</a></small><br><br>'''
    warning = '''--------------------------------------------------------------------------------------<br><small><b>PLEASE NOTE:</b> Failure to update DNS may result in viewers viewing the old website with old content. If you do not move DNS and continue to make changes to your website, these change will not carry over to your new service. &nbsp;Any DNS changes you make can take up to 48 hours to reflect on the Internet.<br></small>--------------------------------------------------------------------------------------<br><br>'''
    temporary = '''In addition, you will need to complete the following to finish your migration:<br><br><small>&bull; &nbsp;<a href="http://help.securepaynet.net/article/8344">Change the primary domain</a> on the old hosting from <b>{0}</b> to <b>old.{0}</b><br>&bull; &nbsp;Change the domain on the new hosting account from <b>{1}</b> to <b>{0}</b> and point the domain to the new location.<br><br></small>'''
    close = '''Please contact us right away if you notice any issues with this migration. Please keep in mind that we will be unable to troubleshoot or provide assistance with issues that arise after 14 days from the migration completion date.<br><br>Should you have any further questions, you can reach us by phone 24/7 at ''' + phone + ''', or simply reply to this email.<br><br />
{3}<br />
{4} Services'''
    if hostsfile == False:
        hosts = ''
    if platform:
        server = ''
        cpanel = ''
        plesk = ''
    else:
        if panel == 2:
            plesk = ''
        else:
            cpanel = ''
    if temp is None:
        temporary = ''
        temp = domain
    output = bcolors.OKBLUE + "IRIS Notes: \n" + bcolors.FAIL + "#fms "
    if fms == 'Expert':
        output = output + "#ctmigrate "
    else:
        output = output + "#migration "
    output = output + "Resolved out ticket for migration of {0} to account with address {1}.\n\n".format(domain, ip) + bcolors.ENDC
    output = output + (email + hosts + live + server + cpanel + plesk + warning + temporary + close).format(domain, temp, ip, signature, fms) + bcolors.ENDC
    return output

if __name__ == '__main__':
    '''Questionairre segment of the migration template generator. Primary method of use if you don't want to call the function directly.'''
    fms = 'Expert' #Setting default as it does not always come up.
    print(bcolors.OKBLUE + "Welcome to IRIS Generator 2.32!\n\nNow, let's get started. Is the destination a 1) server or 2) shared?" + bcolors.ENDC)
    platform = input().lower()
    if platform == '1' or platform == 'server':
        platform = 0 # Resetting to int for re-use in tuple and format lookups.
        print(bcolors.OKBLUE + "Is this for FMS?" + bcolors.ENDC)
        fmsbool = input().lower()
        try:
            if strtobool(fmsbool):
                fms = 'Managed'
        except ValueError:
            print(bcolors.FAIL + "That was a yes or a no question, and you entered: " + fmsbool + "\nI hope you're proud of yourself. I'm going to go kill myself now." + bcolors.ENDC)
            sys.exit()
    elif platform == '2' or platform == 'shared':
        platform = 1
        panel = 1
    else:
        print(bcolors.FAIL + "Uh... type something valid please." + bcolors.ENDC)
        sys.exit()
    print(bcolors.OKBLUE + ("Okay, so we're on a {" + str(platform) +  "}.").format(*mig_tuple) + bcolors.ENDC)
    if platform == 0:
        print(bcolors.OKBLUE + "1) cPanel, 2) Plesk or 3) other?" + bcolors.ENDC)
        panel = input().lower()
        if panel == '1' or panel == 'cpanel':
            panel = 2
        elif panel == '2' or panel == 'plesk':
            panel = 3
        else:
            panel = 4

    print(bcolors.OKBLUE + "What domain did we move to this " + mig_tuple[platform] + "?" + bcolors.ENDC)
    domain = input().lower()
    temp = None
    if platform == 1:
        print(bcolors.OKBLUE + "Was a temporary domain set?" + bcolors.ENDC)
        tempdirbool = input().lower()
        try:
            if bool(strtobool(tempdirbool)):
                print(bcolors.OKBLUE + "What is the temporary domain set to?" + bcolors.ENDC)
                temp = input().lower()
        except ValueError:
            print(bcolors.FAIL + "That was a yes or a no question, and you entered: " + tempdirbool + "\nI hope you're proud of yourself. I'm going to go kill myself now." + bcolors.ENDC)
            sys.exit()

    print(bcolors.OKBLUE + "What's the IP address of this " + mig_tuple[platform] + "?" + bcolors.ENDC)
    ip = input()
    print(bcolors.OKBLUE + "Finally, do we need hosts instructions?" + bcolors.ENDC)
    hostsbool = input().lower()
    try:
        hostsfile = bool(strtobool(hostsbool))
    except ValueError:
        print(bcolors.FAIL + "That was a yes or a no question, and you entered: " + hostsbool + "\nI hope you're proud of yourself. I'm going to go kill myself now." + bcolors.ENDC)
        sys.exit()
    output = (bcolors.OKBLUE + "Outputting: We moved " + domain + " to this {" + str(panel) + "} {" + str(platform) + "} on IP " + ip).format(*mig_tuple)
    if isinstance(temp, str):
        output = output + " with the temporary domain {0}".format(temp)
    if hostsfile:
        output = output + " and we need hosts file instructions"
    print(output + bcolors.ENDC)
    print(bcolors.ENDC + generate(platform, panel, domain, temp, ip, hostsfile, fms, "YOUR NAME HERE"))
