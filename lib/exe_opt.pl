#!perl -w
#
# $Id: exe_opt.pl,v 1.2 2003/06/01 15:53:46 epaepa Exp $
#
# This is a simple script to generate options so PerlApp can make the EXE
# it needs time values, so might as well put it in a perl script!
# (windows has a limited date function)
#
# Robert Eden rmeden@yahoo.com
#

#
# output constants
#
print '-nologo
-force
-trim="Convert::EBCDIC;DB_File;Encode;HASH;HTML::FromText;Text::Iconv;Unicode::Map8;v5"
-info CompanyName="XMLTV Project http://membled.com/work/apps/xmltv/"
-info FileDescription="EXE bundle of XMLTV tools to manage TV Listings"
-info InternalName=xmltv.exe
-info OriginalFilename=xmltv.exe
-info ProductName=xmltv
-info LegalCopyright="GNU General Public License http://www.gnu.org/licenses/gpl.txt"
';

#
# put date in file version field
#
@date=localtime; $date[4]++; $date[5]+=1900;
printf "-info FileVersion=%4d.%d.%d.%d\n",@date[5,4,3,2];

#
# last fields in product version should ommitable, but it doesn't work.
#
$version=shift;
printf "-info ProductVersion=%d.%d.%d.%d\n",split(/\./,$version);
