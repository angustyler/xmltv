# $Id: ZapListings.pm,v 1.30 2003/01/28 16:53:29 jveldhuis Exp $

#
# Special thanks to Stephen Bain for helping me play catch-up with
# zap2it site changes.
#

package XMLTV::ZapListings::ScrapeRow;

use strict;

use vars qw(@ISA);

@ISA = qw(HTML::Parser);

require HTML::Parser;

sub start($$$$$)
{
    my($self,$tag,$attr,$attrseq,$orig) = @_;

    if ( $tag=~/^t[dh]$/io ) {
	$self->{infield}++;
    }

    if ( $self->{infield} ) {
	my $thing;
	$thing->{starttag}=$tag;
	if ( keys(%{$attr}) != 0 ) {
	    $thing->{attr}=$attr;
	}
	push(@{$self->{Cell}->{things}}, $thing);
    }
}

sub text($$)
{
    my ($self,$text) = @_;

    if ( $self->{infield} ) {
	my $thing;

	$thing->{text}=$text;
	push(@{$self->{Cell}->{things}}, $thing);
    }
}

sub end($$)
{
    my ($self,$tag) = @_;

    if ( $tag=~/^t[dh]$/io ) {
	$self->{infield}--;

	my $thing;

	$thing->{endtag}=$tag;
	push(@{$self->{Cell}->{things}}, $thing);

	push(@{$self->{Row}}, @{$self->{Cell}->{things}});
	delete($self->{Cell});
    }
    else {
	if ( $self->{infield} ) {
	    my $thing;

	    $thing->{endtag}=$tag;
	    push(@{$self->{Cell}->{things}}, $thing);
	}
    }
}

#
# summarize in a single string the html we found.
#
sub summarize($)
{
    my $self=shift;

    if ( defined($self->{Cell}) ) {
	#main::errorMessage("warning: cell in row never closed, shouldn't happen\n");
	return("");
	#push(@{$self->{Row}}, @{$self->{Cell}->{things}});
	#delete($self->{Cell});
    }

    my $desc="";
    foreach my $thing (@{$self->{Row}}) {
	if ( $thing->{starttag} ) {
	    $desc.="<$thing->{starttag}>";
	}
	elsif ( $thing->{endtag} ) {
	    $desc.="</$thing->{endtag}>";
	}
	elsif ( $thing->{text} ) {
	    $desc.="<text>$thing->{text}</text>";
	}
    }
    return($desc);
}

sub getSRC($$)
{
    my ($self, $index)=@_;

    my @arr=@{$self->{Row}};
    my $thing=$arr[$index-1];

    #main::errorMessage("item $index : ".XMLTV::ZapListings::Scraper::dumpMe($thing)."\n");
    if ( $thing->{starttag}=~m/img/io ) {
	return($thing->{attr}->{src}) if ( defined($thing->{attr}->{src}) );
	return($thing->{attr}->{SRC}) if ( defined($thing->{attr}->{SRC}) );
    }
    return(undef);
}

sub getHREF($$)
{
    my ($self, $index)=@_;

    my @arr=@{$self->{Row}};
    my $thing=$arr[$index-1];

    #main::errorMessage("item $index : ".XMLTV::ZapListings::Scraper::dumpMe($thing)."\n");
    if ( $thing->{starttag}=~m/a/io) {
	return($thing->{attr}->{href}) if ( defined($thing->{attr}->{href}) );
	return($thing->{attr}->{HREF}) if ( defined($thing->{attr}->{HREF}) );
    }

    return(undef);
}

1;

package XMLTV::ZapListings;

use strict;

use HTTP::Cookies;
use HTTP::Request::Common;
use URI;

sub new
{
    my ($type) = shift;
    my $self={ @_ };            # remaining args become attributes

    my $code;
    $code=$self->{PostalCode} if ( defined($self->{PostalCode}) );
    $code=$self->{ZipCode} if ( defined($self->{ZipCode}) );

    if ( !defined($code) ) {
      main::errorMessage("ZapListings::new requires PostalCode or ZipCode defined\n");
	exit(1);
    }
    $self->{GeoCode}=$code;
    $self->{Debug}=0 if ( !defined($self->{Debug}) );
    $self->{httpHost}=getHttpHost();

    $self->{cookieJar}=HTTP::Cookies->new();

    $self->{ua}=XMLTV::ZapListings::RedirPostsUA->new('cookie_jar'=>$self->{cookieJar});
    if ( 0 && ! $self->{ua}->passRequirements($self->{Debug}) ) {
	main::errorMessage("version of ".$self->{ua}->_agent()." doesn't handle cookies properly\n");
	main::errorMessage("upgrade to 5.61 or later and try again\n");
	return(undef);
    }

    bless($self, $type);

    $self->setupSession();

    return($self);
}

sub getHttpHost()
{
    return("tvlistings2.zap2it.com");
}

# request the initial page so that the ASPSESSION* cookie is set.
sub setupSession($)
{
    my $self=shift;
    my ($ua, $code, $httphost) = @_;

    # some of the pages seem to require these cookies to be set
    $self->{ua}->cookie_jar->set_cookie(0,'bhCookie','1','/',$self->{httpHost},undef,0,0,10000,0);
    $self->{ua}->cookie_jar->set_cookie(0,'popunder','yes','/',$self->{httpHost},undef,0,0,10000,0);

    my $req = GET("http://$self->{httpHost}/partnerinfo.asp?URL=/index.asp&zipcode=$self->{GeoCode}");

    # Redirections are disabled while requesting this page, as the required
    # cookie will be send in the first response.
    my $x = $self->{ua}->requests_redirectable();
    $self->{ua}->requests_redirectable([]);

    $self->{ua}->request($req);

    $self->{ua}->requests_redirectable($x);
}

sub getUserAgent($)
{
    my $self=shift;
    return($self->{ua});
}

sub getCookieJar($)
{
    my $self=shift;
    return($self->{cookieJar});
}

sub doRequest($$$$)
{
    my ($ua, $req, $debug)=@_;

    if ( $debug ) {
      main::statusMessage("==== req ====\n".$req->as_string());
    }

    my $cookie_jar=$ua->cookie_jar();
    if ( defined($cookie_jar) ) {
	if ( $debug ) {
	    main::statusMessage("==== request cookies ====\n".$cookie_jar->as_string()."\n");
	    main::statusMessage("==== sending request ====\n");
	}
    }

    my $res = $ua->request($req);
    if ( $debug ) {
	main::statusMessage("==== got response ====\n");
    }

    $cookie_jar=$ua->cookie_jar();
    if ( defined($cookie_jar) ) {
	if ( $debug ) {
	    main::statusMessage("==== response cookies ====\n".$cookie_jar->as_string()."\n");
	}
    }

    if ( $debug ) {
	main::statusMessage("==== status: ".$res->status_line." ====\n");
    }

    if ( $debug ) {
	if ($res->is_success) {
	    main::statusMessage("==== success ====\n");
	}
	elsif ($res->is_info) {
	    main::statusMessage("==== what's an info response? ====\n");
	}
	else {
	    main::statusMessage("==== bad code ".$res->code().":".HTTP::Status::status_message($res->code())."\n");
	}
	#main::statusMessage("".$res->headers->as_string()."\n");
	#dumpPage($res->content());
	#main::statusMessage("".$res->content()."\n");
    }
    return($res);
}

sub getProviders($)
{
    my ($self)=@_;

    my $debug=$self->{Debug};

    my $req=GET("http://$self->{httpHost}/system.asp?partner_id=national&zipcode=$self->{GeoCode}");

    # actually attempt twice since first time in, we get a cookie that
    # works for the second request
    my $res=&doRequest($self->{ua}, $req, $debug);

    # looks like some requests require two identical calls since
    # the zap2it server gives us a cookie that works with the second
    # attempt after the first fails
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($self->{ua}, $req, $debug);
    }

    if ( !$res->is_success ) {
	main::errorMessage("zap2it failed to give us a page: ".$res->code().":".
			 HTTP::Status::status_message($res->code())."\n");
	main::errorMessage("check postal/zip code or www site (maybe they're down)\n");
	return(undef);
    }

    my $content=$res->content();
    if ( $debug ) {
	open(FD, "> providers.html") || die "providers.html:$!";
	print FD $content;
	close(FD);
    }

    if ( $content=~m/(We do not have information for the zip code[^\.]+)/i ) {
	main::errorMessage("zap2it says:\"$1\"\ninvalid postal/zip code\n");
	return(undef);
    }

    if ( $debug ) {
	if ( !$content=~m/<Input type="hidden" name="FormName" value="edit_provider_list.asp">/ ) {
	    main::errorMessage("Warning: form may have changed(1)\n");
	}
	if ( !$content=~m/<input type="submit" value="See Listings" name="saveProvider">/ ) {
	    main::errorMessage("Warning: form may have changed(2)\n");
	}
	if ( !$content=~m/<input type="hidden" name="zipCode" value="$self->{GeoCode}">/ ) {
	    main::errorMessage("Warning: form may have changed(3)\n");
	}
	if ( !$content=~m/<input type="hidden" name="ziptype" value="new">/ ) {
	    main::errorMessage("Warning: form may have changed(4)\n");
	}
	if ( !$content=~m/<input type=submit value="Confirm Channel Lineup" name="preview">/ ) {
	    main::errorMessage("Warning: form may have changed(5)\n");
	}
    }

    my @providers;
    while ( $content=~s/<SELECT(.*)(?=<\/SELECT>)//ios ) {
        my $options=$1;
        while ( $options=~s/<OPTION value="(\d+)">([^<]+)<\/OPTION>//ios ) {
	    my $p;
	    $p->{id}=$1;
	    $p->{description}=$2;
            #main::debugMessage("provider $1 ($2)\n";
	    push(@providers, $p);
        }
    }
    if ( !@providers ) {
	main::errorMessage("zap2it gave us a page with no service provider options\n");
	main::errorMessage("check postal/zip code or www site (maybe they're down)\n");
	main::errorMessage("(LWP::UserAgent version is ".$self->{ua}->_agent().")\n");
	return(undef);
    }
    return(@providers);
}

sub getChannelList($$$)
{
    my ($self, $provider)=@_;

    my $debug=$self->{Debug};

    my $req = POST("http://$self->{httpHost}/system.asp?partner_id=national&zipcode=$self->{GeoCode}",
		   [saveProvider=>"See Listings",
		    zipcode=>"$self->{GeoCode}",
		    provider=>"$provider",
		    FormName=>'system.asp',
		    btnPreviewYes=>'Confirm Channel Lineup',
		    page_from=>''
		    ]);

    my $res=&doRequest($self->{ua}, $req, $debug);
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($self->{ua}, $req, $debug);
    }

    $req=GET("http://$self->{httpHost}/listings_redirect.asp\?spp=0");
    $res=&doRequest($self->{ua}, $req, $debug);

    # looks like some requests require two identical calls since
    # the zap2it server gives us a cookie that works with the second
    # attempt after the first fails
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&doRequest($self->{ua}, $req, $debug);
    }

    if ( !$res->is_success ) {
	main::errorMessage("zap2it failed to give us a page: ".$res->code().":".
			 HTTP::Status::status_message($res->code())."\n");
	main::errorMessage("check postal/zip code or www site (maybe they're down)\n");
	return(undef);
    }

    my $content=$res->content();
    if ( 0 && $content=~m/>(We are sorry, [^<]*)/ig ) {
	my $err=$1;
	$err=~s/\n/ /og;
	$err=~s/\s+/ /og;
	$err=~s/^\s+//og;
	$err=~s/\s+$//og;
	main::errorMessage("ERROR: $err\n");
	exit(1);
    }
    #$content=~s/>\s*</>\n</g;

    # Probably this is not needed?  I think that calling dumpPage() if
    # an error occurs is probably better.  -- epa
    # 
    if ( $debug ) {
	open(FD, "> channels.html") || die "channels.html: $!";
	print FD $content;
	close(FD);
    }

    my @channels;

    my $rowNumber=0;
    my $html=$content;
    $html=~s/<TR/<tr/og;
    $html=~s/<\/TR/<\/tr/og;

    for my $row (split(/<tr/, $html)) {
	# nuke everything leading up to first >
	# which amounts to html attributes of <tr used in split
	$row=~s/^[^>]*>//so;
	$row=~s/<\/tr>.*//so;

	$rowNumber++;

	# remove space from leading space (and newlines) on every line of html
	$row=~s/[\r\n]+\s*//og;

	my $result=new XMLTV::ZapListings::ScrapeRow()->parse($row);

	my $desc=$result->summarize();
	next if ( !$desc );

	my $nchannel;

	if ( $desc=~m;^<td><img><br><font><b><a><text>([^<]+)</text><br><nobr><text>([^<]+)</text></nobr></a></b></font></td>;o ||
	     $desc=~m;^<td><img><br><b><a><font><text>([^<]+)</text><br><nobr><text>([^<]+)</text></nobr></a></b></font></td>;o ){
	    $nchannel->{number}=$1;
	    $nchannel->{letters}=$2;

	    # img for icon
	    my $ref=$result->getSRC(2);
	    if ( !defined($ref) ) {
		main::errorMessage("row decode on item 2 failed on '$desc'\n");
		dumpPage($content);
		return(undef);
	    }
	    else {
		my $icon=URI->new_abs($ref, "http://$self->{httpHost}/");
		$nchannel->{icon}=$icon;
	    }

	    # <a> gives url that contains station_num
	    my $offset=0;
	    if ( $desc=~m;^<td><img><br><font><b><a>;o ) {
		$offset=6;
	    }
	    elsif ( $desc=~m;^<td><img><br><b><a>;o ) {
		$offset=5;
	    }
	    else {
	      main::errorMessage("coding error finding <a> in $desc\n");
		return(undef);
	    }
	    $ref=$result->getHREF($offset);
	    if ( !defined($ref) ) {
		main::errorMessage("row decode on item $offset failed on '$desc'\n");
		dumpPage($content);
		return(undef);
	    }

	    if ( $ref=~m;listings_redirect.asp\?station_num=(\d+);o ) {
		$nchannel->{stationid}=$1;
	    }
	    else {
		main::errorMessage("row decode on item 6 href failed on '$desc'\n");
		dumpPage($content);
		return(undef);
	    }
	}
	elsif ( $desc=~m;^<td><font><b><a><text>([^<]+)</text><br><nobr><text>([^<]+)</text></nobr></a></b></font></td>;o ||
		$desc=~m;^<td><b><a><font><text>([^<]+)</text><br><nobr><text>([^<]+)</text></nobr></a></b></font></td>;o ) {
	    $nchannel->{number}=$1;
	    $nchannel->{letters}=$2;

	    # <a> gives url that contains station_num
	    my $offset;
	    if ( $desc=~m;^<td><font><b><a>;o ) {
		$offset=4;
	    }
	    elsif ( $desc=~m;^<td><b><a>;o ) {
		$offset=3;
	    }
	    else {
	      main::errorMessage("coding error finding <a> in $desc\n");
		return(undef);
	    }
	    my $ref=$result->getHREF($offset);
	    if ( !defined($ref) ) {
		main::errorMessage("row decode on item $offset failed on '$desc'\n");
		dumpPage($content);
		return(undef);
	    }
	    if ( $ref=~m;listings_redirect.asp\?station_num=(\d+);o ) {
		$nchannel->{stationid}=$1;
	    }
	    else {
		main::errorMessage("row decode on item $offset href failed on '$desc'\n");
		dumpPage($content);
		return(undef);
	    }
	}
	else {
	    # ignored
	}

	if ( defined($nchannel) ) {
	    push(@channels, $nchannel);
	}
    }

    if ( ! @channels ) {
	main::errorMessage("zap2it gave us a page with no channels\n");
	dumpPage($content);
	return(undef);
    }

    foreach my $channel (@channels) {
	# default is channel is in listing
	if ( defined($channel->{number}) && defined($channel->{letters}) ) {
	    $channel->{description}="$channel->{number} $channel->{letters}"; 
	}
	else {
	    $channel->{description}.="$channel->{number}" if ( defined($channel->{number}) );
	    $channel->{description}.="$channel->{letters}" if ( defined($channel->{letters}) );
	}
	$channel->{station}=$channel->{description};
    }

    return(@channels);
}

# Write an offending HTML page to a file for debugging.
my $dumpPage_counter;

sub dumpPage($)
{
    my $content = shift;
    $dumpPage_counter = 0 if not defined $dumpPage_counter;
    $dumpPage_counter++;
    my $filename = "ZapListings.dump.$dumpPage_counter";
    local *OUT;
    if (open (OUT, ">$filename")) {
	main::errorMessage("dumping HTML page to $filename\n");
	print OUT $content
	  or warn "cannot dump HTML page to $filename: $!";
	close OUT or warn "cannot close $filename: $!";
    }
    else {
	warn "cannot dump HTML page to $filename: $!";
    }
}

1;


########################################################
#
# little LWP::UserAgent that accepts redirects
#
########################################################
package XMLTV::ZapListings::RedirPostsUA;
use HTTP::Request::Common;

# include LWP separately to verify minimal requirements on version #
use LWP 5.62;
use LWP::UserAgent;

use vars qw(@ISA);
@ISA = qw(LWP::UserAgent);

#
# manually check requirements on LWP (libwww-perl) installation
# leaving this subroutine here in case we need something less
# strict or more informative then what 'use LWP 5.60' gives us.
# 
sub passRequirements($$)
{
    my ($self, $debug)=@_;
    my $haveVersion=$LWP::VERSION;

  main::debugMessage("requirements check: have $self->_agent(), require 5.61\n");

    if ( $haveVersion=~/(\d+)\.(\d+)/ ) {
	if ( $1 < 5 || ($1 == 5 && $2 < 61) ) {
	    die "$0: requires libwww-perl version 5.61 or later, (you have $haveVersion)";
	    return(0);
	}
    }
    # pass
    return(1);
}

#
# add env_proxy flag to constructed UserAgent.
#
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_, env_proxy => 1,
				  timeout => 180);
    bless ($self, $class);
    #$self->agent('Mozilla/5.0');
    return $self;
}

sub redirect_ok { 1; }
1;

########################################################
# END
########################################################

package XMLTV::ZapListings::Scraper;

use HTTP::Request::Common;

sub new
{
    my ($type) = shift;
    my $self={ @_ };            # remaining args become attributes

    if ( ! defined($self->{PostalCode}) &&
	 ! defined($self->{ZipCode}) ) {
	die "no PostalCode or ZipCode specified in create";
    }

    # create own own ZapListings handle each time
    $self->{zl}=new XMLTV::ZapListings('PostalCode'=>$self->{PostalCode},
				       'ZipCode' => $self->{ZipCode},
				       'Debug' => $self->{Debug});

    # since I know we don't care, lets pretend there's only one code :)
    if ( defined($self->{PostalCode}) ) {
	$self->{ZipCode}=$self->{PostalCode};
	delete($self->{PostalCode});
    }

    die "no ProviderID specified in create" if ( ! defined($self->{ProviderID}) );

    $self->{httphost}=XMLTV::ZapListings::getHttpHost();

    my $req = POST("http://$self->{httphost}/system.asp?partner_id=national&zipcode=$self->{ZipCode}",
		   [saveProvider=>"See Listings",
		    zipcode=>"$self->{ZipCode}",
		    provider=>"$self->{ProviderID}",
		    FormName=>'system.asp',
		    btnPreviewYes=>'Confirm Channel Lineup',
		    page_from=>''
		    ]);

    # initialize listings cookies
    my $res=&XMLTV::ZapListings::doRequest($self->{zl}->getUserAgent(), $req, $self->{Debug});
    if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	# again.
	$res=&XMLTV::ZapListings::doRequest($self->{zl}->getUserAgent(), $req, $self->{Debug});
    }

    bless($self, $type);
    return($self);
}

sub getCookieJar($)
{
    my $self=shift;
    return($self->{zl}->getCookieJar());
}

use HTML::Entities qw(decode_entities);

sub massageText
{
    my ($text) = @_;

    $text=~s/&nbsp;/ /og;
    $text=~s/&nbsp$/ /og;
    $text=decode_entities($text);
    $text=~s/\240/ /og;
    $text=~s/^\s+//o;
    $text=~s/\s+$//o;
    $text=~s/\s+/ /o;
    return($text);
}

sub dumpMe($)
{
    require Data::Dumper;
    my $s = $_[0];
    my $d = Data::Dumper::Dumper($s);
    $d =~ s/^\$VAR1 =\s*//;
    $d =~ s/;$//;
    chomp $d;
    return $d;
}

sub setValue($$$$)
{
    my ($self, $hash_ref, $key, $value)=@_;
    my $hash=$$hash_ref;

    if ( $self->{Debug} ) {
	if ( defined($hash->{$key}) ) {
	    main::errorMessage("replaced value '$key' from '$hash->{$key}' to '$value'\n");
	}
	else {
	    main::errorMessage("set value '$key' to '$value'\n");
	}
    }
    $hash->{$key}=$value;
    return($hash)
}

#
# scraping html, here's the theory behind this madness.
# 
# heres the pseudo code is something like:
#    separate the rows of all html tables
#    for each row that looks like a listings row
#      parse and summarize the row in a single string
#      of xml, with start/end elements (no attributes)
#      that correspond with the html start/end tags
#      along with "text" elements around text html elements.
#
#    This gives us a single string we can do regexp against
#    to pull out the information based on the tags around
#    elements.
#
#    benefit of this approach is we get to pull elements out
#    if we can decipher how the html encoder is dealing with
#    them, for instance, subtitles at zap2it appear with <i>
#    tags around them, we can use this to know for certain
#    we're getting the subtitle of the program. Another one is
#    the title of the program is always bolded (<b>) so that
#    makes it easier.
#
#    Anything we can't decipher for certain gets the text pulled
#    out and we see if it only contains program qualifiers. If
#    so, we decode them and move on. If not we make some assumptions
#    about what the text might be, based on its position in the
#    html. The problem here is we can't decipher all qualifiers
#    because the entire list isn't known to us. We add as we go.
#
#    In the end anything left over we match against what we've
#    had left over after successful scrapes and if it differs
#    we emit an error since it means either the format has
#    changed or it contains info we didn't scrape properly.
#    
my %warnedCandidateDetail;
sub scrapehtml($$$)
{
    my ($self, $html, $htmlsource)=@_;

    # declare known languages here so we can more precisely identify
    # them in program details
    my @knownLanguages=qw(
			  Aboriginal
			  Arabic
			  Armenian
			  Cambodian
			  Cantonese
			  Chinese
			  Colonial
			  Cree
			  Dene
			  Diwlai
			  English
			  Farsi
			  French
			  German
			  Greek
			  Gujarati
			  Hindi
			  Hmong
			  Hungarian
			  Innu
			  Inuktitut
			  Inkutitut
			  Inukutitut
			  Inunktitut
			  Inuvialuktun
			  Italian
			  Italianate
			  Iranian
			  Japanese
			  Khmer
			  Korean
			  Mandarin
			  Mi'kmaq
			  Mohawk
			  Musgamaw
			  Oji
			  Ojibwa
			  Panjabi
			  Polish
			  Portuguese
			  Punjabi
			  Quechuan
			  Romanian
			  Russian
			  Spanish
			  Swedish
			  Tagalog
			  Tamil
			  Tlingit
			  Ukrainian
			  Urdu
			  Vietnamese
			  );

    my $rowNumber=0;
    $html=~s/<TR/<tr/og;
    $html=~s/<\/TR/<\/tr/og;

    my @programs;
    for my $row (split(/<tr/, $html)) {
	# nuke everything leading up to first >
	# which amounts to html attributes of <tr used in split
	$row=~s/^[^>]*>//so;

	# skipif the split didn't end with a row end </tr>
	#next if ( !($row=~s/[\n\r\s]*<\/tr>[\n\r\s]*$//iso));
	$row=~s/<\/tr>.*//so;
	#main::debugMessage("working on: $row\n");
	#next if ( !($row=~s/<\/tr>[\n\r\s]*$//iso));

	# ignore if more than one ending </tr> because they signal
	# imbedded tables - I think.
	next if ( $row=~m/<\/tr>/io);
	#$row=~s/(<\/tr>).*/$1/og;

	$rowNumber++;

	# remove space from leading space (and newlines) on every line of html
	$row=~s/[\r\n]+\s*//og;

	# should now be similar to:
	# <TD width="15%" valign="top" align="right"><B>12:20 AM</B></TD>
	# <TD width="5%"></TD><TD width="80%" valign="top">
	# <FONT face="Helvetica,Arial" size="2">
	# <B><A href="progdetails.asp\?prog_id=361803">Open Mike With Mike Bullard</A></B>
	# (<A href="textone.asp\?station_num=15942\&amp;cat_id=31">Talk / Tabloid</A>)
	#     CC Stereo  </FONT><FONT face="Helvetica,Arial" size="-2">  (ends at 01:20)
	#</TD>

	#main::debugMessage("IN: $rowNumber: $row\n");

	# run it through our row scaper that separates out the html
	my $result=new XMLTV::ZapListings::ScrapeRow()->parse($row);

	# put together a summary of what we found
	my $desc=$result->summarize();
	next if ( !$desc );

	# now we have something that resembles:
	# <td><b><text>....</text></b><td> etc.
	# 
	my $prog;
	if ( $self->{DebugListings} ) {
	   $prog->{precomment}=$desc;
 	}
	main::debugMessage("ROW: $rowNumber: $desc\n") if ( $self->{Debug} );

	if ( $desc=~s;^<td><b><text>([0-9]+):([0-9][0-9]) ([AP]M)</text></b></td><td></td>;;io ||
	     $desc=~s;^<td><font><b><text>([0-9]+):([0-9][0-9]) ([AP]M)</text></b></font></td><td></td>;;io ) {
	    my $posted_start_hour=scalar($1);
	    my $posted_start_min=scalar($2);
	    my $pm=($3=~m/^p/io); #PM

	    $prog=$self->setValue(\$prog, "start_hour", $posted_start_hour);
	    $prog=$self->setValue(\$prog, "start_min", $posted_start_min);

	    if ( $pm && $prog->{start_hour} != 12 ) {
		$self->setValue(\$prog, "start_hour", $prog->{start_hour}+12);
	    }
	    elsif ( !$pm && $prog->{start_hour} == 12 ) {
		# convert 24 hour clock ( 12:??AM to 0:??AM )
		$self->setValue(\$prog, "start_hour", 0);
	    }

	    if ( $desc=~s;<font><text>(.*?)\s*\(ends at ([0-9]+):([0-9][0-9])\)(.*?)</text></td>$;;io ||
		 $desc=~s;<font><text>(.*?)\s*\(ends at ([0-9]+):([0-9][0-9])\)\&nbsp\;(.*?)</text><br><a><img></a></td>$;;io){
		my $preRest=$1;
		my $posted_end_hour=$2;
		my $posted_end_min=$3;
		my $postRest=$4;

		$self->setValue(\$prog, "end_hour", scalar($2));
		$self->setValue(\$prog, "end_min", $3);

		if ( defined($postRest) && length($postRest) ) {
		    $postRest=~s/^\&nbsp\;//o;
		}
		if ( !defined($postRest) || !length($postRest) ) {
		    $postRest="";
		}

		if ( defined($preRest) && length($preRest) ) {
		    #if ( $self->{Debug} ) {
			#main::debugMessage("prereset: $preRest\n");
		    #}
		    if ( $preRest=~s;\s*(\*+)\s*$;; ) {
		        if ( length($1) > 4 ) {
		           main::statusMessage("star rating of $1 is > expected 4, notify xmltv-users\@lists.sf.net\n");
		        }
			$self->setValue(\$prog, "star_rating", sprintf("%d/4", length($1)));
		    }
		    elsif ( $preRest=~s;\s*(\*+)(\s*)(1/2)\s*$;; ||
			    $preRest=~s;\s*(\*+)(\s*)(\+)\s*$;; ) {
		        if ( length($1) > 4 ) {
		           main::statusMessage("star rating of $1$2$3 is > expected 4, notify xmltv-users\@lists.sf.net\n");
		        }
			$self->setValue(\$prog, "star_rating", sprintf("%d.5/4", length($1)));
		    }
		    else {
			if ( $self->{Debug} ) {
		           main::debugMessage("FAILED to decode what we think should be star ratings\n");
			   main::debugMessage("\tsource: $htmlsource\n\tdecode failed on:'$preRest'\n");
			}
		    }
		}
		if ( length($preRest) || length($postRest) ) {
		    $desc.="<font><text>";
		    if ( length($preRest) && length($postRest) ) {
			$desc.="$preRest&nbsp;$postRest";
		    }
		    elsif ( length($preRest) ) {
			$desc.="$preRest";
		    }
		    else {
			$desc.="$postRest";
		    }
		    # put back reset of the text since sometime the (ends at xx:xx) is tacked on
		    $desc.="</text></td>";
		    if ( $self->{Debug} ) {
			main::debugMessage("put back details, now have '$desc'\n");
		    }
		}
	    }
	    else {
	      main::errorMessage("FAILED to find endtime\n");
	      main::errorMessage("\tsource: $htmlsource\n");
	      main::errorMessage("\thtml:'$desc'\n");
	    }

	    if ( defined($prog->{end_hour}) ) {
		# anytime end hour is < start hour, end hour is next morning
		# posted start time is 12 am and end hour is also 12 then adjust
		if ( $prog->{start_hour} == 0 && $prog->{end_hour}==12 ) {
		    $self->setValue(\$prog, "end_hour", 0);
		}
		# prog starting after 6 with posted start > end hour
		elsif ( $prog->{start_hour} > 18 && $posted_start_hour > $prog->{end_hour} ) {
		    $self->setValue(\$prog, "end_hour", $prog->{end_hour}+24);
		}
		# if started in pm and end was not 12, then adjustment to 24 hr clock
		elsif ( $prog->{start_hour} > $prog->{end_hour} ) {
		    $self->setValue(\$prog, "end_hour", $prog->{end_hour}+12);
		}
	    }

	    if ( $desc=~s;<b><a><text>\s*(.*?)\s*</text></a></b>;;io ) {
		$self->setValue(\$prog, "title", massageText($1));
	    }
	    else {
		if ( $self->{Debug} ) {
		  main::debugMessage("FAILED to find title\n");
		  main::debugMessage("\tsource: $htmlsource\n\thtml:'$desc'\n");
		}
	    }
	    # <i><text>&quot;</text><a><text>Past Imperfect</text></a><text>&quot;</text></i>
	    if ( $desc=~s;<text> </text><i><text>&quot\;</text><a><text>\s*(.*?)\s*</text></a><text>&quot\;</text></i>;;io ) {
		$self->setValue(\$prog, "subtitle", massageText($1));
	    }
	    else {
		if ( $self->{Debug} ) {
		  main::debugMessage("FAILED to find subtitle\n");
		  main::debugMessage("\tsource: $htmlsource\n\thtml:'$desc'\n");
		}
	    }

	    # categories may be " / " separated
	    if ( $desc=~s;<text>\(</text><a><text>\s*(.*?)\s*</text></a><text>\)\s*;<text>;io ) {
		for (split(/\s+\/\s/, $1) ) {
		    push(@{$prog->{category}}, massageText($_));
		}
	    }
	    else {
		if ( $self->{Debug} ) {
		    main::debugMessage("FAILED to find category\n");
		    main::debugMessage("\tsource: $htmlsource\n\thtml:'$desc'\n");
		}
	    }

	    if ( $self->{Debug} ) {
		main::debugMessage("PREEXTRA: $desc\n");
	    }
	    my @extras;
	    while ($desc=~s;<text>\s*(.*?)\s*</text>;;io ) {
		push(@extras, massageText($1)); #if ( length($1) );
	    }
	    if ( $self->{Debug} ) {
		main::debugMessage("POSTEXTRA: $desc\n");
	    }
	    my @leftExtras;
	    for my $extra (reverse(@extras)) {
		my $original_extra=$extra;

		my $resultNotSure;
		my $success=1;
		my @notsure;
		my @sure;
		my @backup;
		main::debugMessage("splitting details '$extra'..\n") if ( $self->{Debug} );
		my @values;
		while ( 1 ) {
		    my $i;
		    if ( defined($extra) ) {
			if ( $extra=~s/\s*(\([^\)]+\))\s*$//o ) {
			    $i=$1;
			}
			else {
			    # catch some cases where they didn't put a space after )
			    # ex. (Repeat)HDTV
			    #
			    if ( $extra=~s/\)([A-Z-a-z]+)$/\)/o ) {
				$i=$1;
			    }
			    else {
				@values=reverse(split(/\s+/, $extra));
				$extra=undef;
				$i=pop(@values);
			    }
			}
		    }
		    else {
			if ( scalar(@values) == 0 ) {
			    last;
			}
			$i=pop(@values);
		    }
		    last if ( !defined($i) );

		    main::debugMessage("checking detail $i..\n") if ( $self->{Debug} );

		    # General page about ratings systems, one at least :)
		    # http://www.attadog.com/splash/rating.html
		    #
		    # www.tvguidelines.org and http://www.fcc.gov/vchip/
		    if ( $i=~m/^TV(Y)$/oi ||
			 $i=~m/^TV(Y7)$/oi ||
			 $i=~m/^TV(G)$/oi ||
			 $i=~m/^TV(PG)$/oi ||
			 $i=~m/^TV(14)$/oi ||
			 $i=~m/^TV(M)$/oi ||
			 $i=~m/^TV(MA)$/oi ) {
			$prog->{ratings_VCHIP}="$1";
			push(@sure, $i);
			next;
		    }
		    # www.filmratings.com
		    elsif ( $i=~m/^(G)$/oi ||
			    $i=~m/^(PG)$/oi ||
			    $i=~m/^(PG-13)$/oi ||
			    $i=~m/^(R)$/oi ||
			    $i=~m/^(NC-17)$/oi ||
			    $i=~m/^(NR)$/oi ||
			    $i=~m/^Rated (G)$/oi ||
			    $i=~m/^Rated (PG)$/oi ||
			    $i=~m/^Rated (PG-13)$/oi ||
			    $i=~m/^Rated (R)$/oi ||
			    $i=~m/^Rated (NC-17)$/oi ||
			    $i=~m/^Rated (NR)$/oi ) {
			$prog->{ratings_MPAA}="$1";
			push(@sure, $i);
			next;
		    }
		    # ESRB ratings http://www.esrb.org/esrb_about.asp
		    elsif ( $i=~/^(AO)$/io || #adults only
			    $i=~/^(EC)$/io || #early childhood
			    $i=~/^(K-A)$/io || # kids to adults
			    $i=~/^(KA)$/io || # kids to adults
			    $i=~/^(E)$/io || #everyone
			    $i=~/^(T)$/io || #teens
			    $i=~/^(M)$/io  #mature
			    ) {
			$prog->{ratings_ESRB}="$1";
			# remove dashes :)
			$prog->{ratings_ESRB}=~s/\-//o;
			push(@sure, $i);
			next;
		    }
		    # we're not sure about years that appear in the
		    # text unless the entire content of the text is
		    # found to be valid and "understood" program details
		    # ( so years that appear in the middle of program descriptions 
		    #   don't count, only when they appear by themselves or in text
		    #   like "CC Stereo 1969" for instance).
		    #
		    elsif ( $i=~/^\d\d\d\d$/io ) {
			$resultNotSure->{year}=$i;
			push(@notsure, $i);
			push(@backup, $i);
			next;
		    }
		    elsif ( $i=~/\((\d\d\d\d)\)/io ) {
			$prog->{year}=$i;
			push(@sure, $i);
			push(@backup, $i);
			next;
		    }
		    elsif ( $i=~/^CC$/io ) {
			$prog->{qualifiers}->{ClosedCaptioned}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^Stereo$/io ) {
			$prog->{qualifiers}->{InStereo}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^HDTV$/io ) {
			$prog->{qualifiers}->{HDTV}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Repeat\)$/io ) {
			$prog->{qualifiers}->{PreviouslyShown}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Taped\)$/io ) {
			$prog->{qualifiers}->{Taped}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Live\)$/io ) {
			$prog->{qualifiers}->{Live}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Call-in\)$/io ) {
			push(@{$prog->{category}}, "Call-in");
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Animated\)$/io ) {
			push(@{$prog->{category}}, "Animated");
			push(@sure, $i);
			next;
		    }
		    # catch commonly imbedded categories
		    elsif ( $i=~/^\(Fiction\)$/io ) {
			push(@{$prog->{category}}, "Fiction");
			next;
		    }
		    elsif ( $i=~/^\(drama\)$/io || $i=~/^\(dramma\)$/io ) { # dramma is french :)
			push(@{$prog->{category}}, "Drama");
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Acci\xf3n\)$/io ) { # action in french :)
			push(@{$prog->{category}}, "Action");
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Comedia\)$/io ) { # comedy in french :)
			push(@{$prog->{category}}, "Comedy");
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(If necessary\)$/io ) {
			$prog->{qualifiers}->{"If Necessary"}++;
			push(@sure, $i);
			next;
		    }
		    elsif ( $i=~/^\(Subject to blackout\)$/io ) {
			$prog->{qualifiers}->{"Subject To Blackout"}++;
			push(@sure, $i);
			next;
		    }
		    # 1re de 2
		    # 2e de 7
		    elsif ( $i=~/^\((\d+)re de (\d+)\)$/io || # part x of y in french :)
			    $i=~/^\((\d+)e de (\d+)\)$/io ) { # part x of y in french :)
			$prog->{qualifiers}->{PartInfo}="Part $1 of $2";
			next;
		    }

		    # ignore sports event descriptions that include team records
		    # ex. (10-1)
		    elsif ( $i=~/^\(\d+\-\d+\)$/o ) {
			main::debugMessage("understood program detail, on ignore list: $i\n") if ( $self->{Debug} );
			# ignored
			next;
		    }
		    # ignore (Cont'd.) and (Cont'd)
		    elsif ( $i=~/^\(Cont\'d\.*\)$/io ) {
			main::debugMessage("understood program detail, on ignore list: $i\n") if ( $self->{Debug} );
			# ignored
			next;
		    }

		    # example "French with English subtitles"
		    # example "French and English subtitles"
		    # example "Japanese; English subtitles"
		    elsif ( $i=~/^\(([^\s]+)\s+with\s+([^\s]+) subtitles\)$/io ||
			    $i=~/^\(([^\s]+)\s+and\s+([^\s]+) subtitles\)$/io ||
			    $i=~/^\(([^\s|;|,|\/]+)[\s;,\/]*\s*([^\s]+) subtitles\)$/io) {
			my $lang=$1;
			my $sub=$2;

			my $found1=0;
			my $found2=0;
			for my $k (@knownLanguages) {
			    $found1++ if ( $k eq $lang );
			    $found2++ if ( $k eq $sub );
			}

			if ( ! $found1 ) {
			  main::statusMessage("identified possible candidate for new language $lang in $i\n");
			}
			if ( ! $found2 ) {
			  main::statusMessage("identified possible candidate for new language $sub in $i\n");
			}
			$prog->{qualifiers}->{Language}=$lang;
			$prog->{qualifiers}->{Subtitles}=$sub;
		    }
		    #
		    # lanuages added as we see them.
		    #
		    else {
			my $declaration=$i;
			if ( $declaration=~s/^\(//o && $declaration=~s/\)$//o ) {
			    # '(Hindi and English)'
			    # '(Hindi with English)'
			    if ( $declaration=~/^([^\s]+)\s+and\s+([^\s]+)$/io ||
				 $declaration=~/^([^\s]+)\s+with\s+([^\s]+)$/io ) {
				my $lang=$1;
				my $sub=$2;
				
				my $found1=0;
				my $found2=0;
				for my $k (@knownLanguages) {
				    $found1++ if ( $k eq $lang );
				    $found2++ if ( $k eq $sub );
				}
				
				# only print message if one matched and the other didn't
				if ( ! $found1 && $found2 ) {
				    main::statusMessage("identified possible candidate for new language $lang in $i\n");
				}
				if ( ! $found2 && $found1 ) {
				    main::statusMessage("identified possible candidate for new language $sub in $i\n");
				}
				if ( $found1 && $found2 ) {
				    $prog->{qualifiers}->{Language}=$lang;
				    $prog->{qualifiers}->{Dubbed}=$sub;
				    next;
				}
			    }
			    
			    # more language checks
			    # '(Hindi, English)'
			    # '(Hindi-English)'
			    # '(English/French)'
			    # '(English/Oji-Cree)'
			    # '(Hindi/Punjabi/Urdu)', but I'm not sure what it means.
			    if ( $declaration=~m;[/\-,];o ) {
				
				my @arr=split(/[\/]|[\-]|[,]/, $declaration);
				my @notfound;
				my $matches=0;
				for my $lang (@arr) {
				    # chop off start/end spaces
				    $lang=~s/^\s*//o;
				    $lang=~s/\s*$//o;

				    my $found=0;
				    for my $k (@knownLanguages) {
					if ( $k eq $lang ) {
					    $found++;
					    last;
					}
				    }
				    if ( !$found ) {
					push(@notfound, $lang);
				    }
				    $matches+=$found;
				}
				if ( $matches == scalar(@arr) ) {
				    # put "lang/lang/lang" in qualifier since we don't know
				    # what it really means.
				    $prog->{qualifiers}->{Language}=$declaration;
				    next;
				}
				elsif ( $matches !=0  ) {
				    # matched 1 or more, warn about rest
				    for my $sub (@notfound) {
					main::statusMessage("identified possible candidate for new language $sub in $i\n");
				    }
				}
			    }

			    if ( 1 ) {
				# check for known languages 
				my $found;
				for my $k (@knownLanguages) {
				    if ( $declaration=~/^$k$/i ) {
					$found=$k;
					last;
				    }
				}

				if ( defined($found) ) {
				    $prog->{qualifiers}->{Language}=$found;
				    push(@sure, $declaration);
				    next;
				}

				if ( $declaration=~/^``/o && $declaration=~/''$/o ) {
				    if ( $self->{Debug} ) {
					main::debugMessage("ignoring what's probably a show reference $i\n");
				    }
				}
				else {
				    main::statusMessage("possible candidate for program detail we didn't identify $i\n")
					unless $warnedCandidateDetail{$i}++;
				}
				$success=0;
				push(@backup, $i);
			    }
			}
			else {
			   $success=0;
			   push(@backup, $i);
			}
		    }
		}

		if ( !$success ) {
		    if ( @notsure ) {
			if ( $self->{Debug} ) {
			  main::debugMessage("\thtml:'$desc'\n");
			  main::debugMessage("\tpartial match on details '$original_extra'\n");
			  main::debugMessage("\tsure about:". join(',', @sure)."\n") if ( @sure );
			  main::debugMessage("\tnot sure about:". join(',', @notsure)."\n") if ( @notsure );
			}
			# we piece the original back using space separation so that the ones
			# we're sure about are removed
			push(@leftExtras, join(' ', @backup));
		    }
		    else {
			main::debugMessage("\tno match on details '".join(',', @backup)."'\n") if ( $self->{Debug} );
			push(@leftExtras, $original_extra);;
		    }
		}
		else {
		    # if everything in this piece parsed as a qualifier, then
		    # incorporate the results, partial results are dismissed
		    # then entire thing must parse into known qualifiers
		    for (keys %$resultNotSure) {
			$self->setValue(\$prog, $_, $resultNotSure->{$_});
		    }
		}
	    }

	    # what ever is left is only allowed to be the description
	    # but there must be only one.
	    if ( @leftExtras ) {
		if ( scalar(@leftExtras) != 1 ) {
		    for (@leftExtras) {
			main::errorMessage("scraper failed with left over details: $_\n");
		    }
		}
		else {
		    $self->setValue(\$prog, "desc", pop(@leftExtras));
		    main::debugMessage("assuming description '$prog->{desc}'\n") if ( $self->{Debug} );
		}
	    }

	    #for my $key (keys (%$prog)) {
		#if ( defined($prog->{$key}) ) {
		#    main::errorMessage("KEY $key: $prog->{$key}\n");
		#}
	    #}

	    if ( $desc ne "<td><font></font>" &&
		 $desc ne "<td><font></font><font></td>" ) {
		main::errorMessage("scraper failed with left overs: $desc\n");
	    }
	    #$desc=~s/<text>(.*?)<\/text>/<text>/og;
	    #main::errorMessage("\t$desc\n");


	    # final massage.

	    my $title=$prog->{title};
	    if ( defined($title) ) {
		# look and pull apart titles like: Nicholas Nickleby   Part 1 of 2
		# putting 'Part X of Y' in PartInfo instead
		if ( $title=~s/\s+Part\s+(\d+)\s+of\s+(\d+)\s*$//o ) {
		    $prog->{qualifiers}->{PartInfo}="Part $1 of $2";
		    $self->setValue(\$prog, "title", $title);
		}
	    }

	    push(@programs, $prog);
	}
    }
    return(@programs);
}

sub readSchedule($$$$$)
{
    my ($self, $stationid, $station_desc, $day, $month, $year)=@_;

    my $content;
    my $cacheFile;

    if ( -f "urldata/$stationid/content-$month-$day-$year.html" &&
	 open(FD, "< urldata/$stationid/content-$month-$day-$year.html") ) {
	main::statusMessage("cache enabled, reading urldata/$stationid/content-$month-$day-$year.html..\n");
	my $s=$/;
	undef($/);
	$content=<FD>;
	close(FD);
	$/=$s;
    }
    else {
	my $ua=XMLTV::ZapListings::RedirPostsUA->new('cookie_jar'=>$self->getCookieJar());

	if ( 0 && ! $ua->passRequirements($self->{Debug}) ) {
	    main::errorMessage("version of ".$ua->_agent()." doesn't handle cookies properly\n");
	    main::errorMessage("upgrade to 5.61 or later and try again\n");
	    return(-1);
	}

	my $req=POST("http://$self->{httphost}/listings_redirect.asp\?partner_id=national",
		     [ displayType => "Text",
		       duration => "1",
		       startDay => "$month/$day/$year",
		       startTime => "0",
		       category => "0",
		       station => "$stationid",
		       goButton => "GO"
		       ]);

	my $res=&XMLTV::ZapListings::doRequest($ua, $req, $self->{Debug});

	# looks like some requests require two identical calls since
	# the zap2it server gives us a cookie that works with the second
	# attempt after the first fails
	if ( !$res->is_success || $res->content()=~m/your session has timed out/i ) {
	    # again.
	    $res=&XMLTV::ZapListings::doRequest($ua, $req, $self->{Debug});
	}

	if ( !$res->is_success ) {
	    main::errorMessage("zap2it failed to give us a page: ".$res->code().":".
			     HTTP::Status::status_message($res->code())."\n");
	    main::errorMessage("check postal/zip code or www site (maybe they're down)\n");
	    return(-1);
	}
	$content=$res->content();
        if ( $content=~m/>(We are sorry, [^<]*)/ig ) {
	   my $err=$1;
	   $err=~s/\n/ /og;
	   $err=~s/\s+/ /og;
	   $err=~s/^\s+//og;
	   $err=~s/\s+$//og;
	   main::errorMessage("ERROR: $err\n");
	   return(-1);
        }
	if ( -d "urldata" ) {
	    $cacheFile="urldata/$stationid/content-$month-$day-$year.html";
	    if ( ! -d "urldata/$stationid" ) {
		mkdir("urldata/$stationid", 0775) || warn "failed to create dir urldata/$stationid:$!";
	    }
	    if ( open(FD, "> $cacheFile") ) {
		print FD $content;
		close(FD);
	    }
	    else {
		warn("unable to write to cache file: $cacheFile");
	    }
	}
    }

    if ( $self->{Debug} ) {
	main::debugMessage("scraping html for $year-$month-$day on station $stationid: $station_desc\n");
    }

    @{$self->{Programs}}=$self->scrapehtml($content, "$year-$month-$day on station $station_desc (id $stationid)");
    if ( scalar(@{$self->{Programs}}) == 0 ) {
	unlink($cacheFile) if ( defined($cacheFile) );

	main::statusMessage("zap2it page format looks okay, but no programs found (no available data yet ?)\n");
	# return un-retry-able
	return(-2);
    }

    # emit delayed message so we only see it when we succeed
    if ( defined($cacheFile) ) {
      main::statusMessage("cache enabled, writing $cacheFile..\n");
    }

  main::statusMessage("Day $year-$month-$day schedule for station $station_desc has:".
		      scalar(@{$self->{Programs}})." programs\n");
    
    return(scalar(@{$self->{Programs}}));
}

sub getPrograms($)
{
    my $self=shift;
    my @ret=@{$self->{Programs}};
    delete($self->{Programs});
    return(@ret);
}

1;


