package ClickListings::ParseTable;

#
# ----------------------------------------------------------------------------
# "THE BEER-WARE LICENSE" (Revision 42):
# <jerry@matilda.com> wrote this file.  As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return.   
# ----------------------------------------------------------------------------
# always wanted to use this licence, thanks Poul-Henning Kamp.
#
# Feel free to contact me with comments, contributions,
# and the like. jerry@matilda.com 
#

#
# $Log: ClickListings.pm,v $
# Revision 1.7  2001/11/11 17:04:35  epaepa
# Changed a lot of 'print STDERR' to 'warn', it makes it clearer what the
# purpose is.  Debug statements didn't change since they're not actually
# warnings.
#
# Revision 1.6  2001/11/11 16:44:19  epaepa
# Whoops, just realized that the last changelog message would itself get
# keyword-expanded, causing no end of confusion.  I had to perform some
# emergency censorship of funny dollar signs.
#
# Revision 1.5  2001/11/11 16:41:05  epaepa
# Rearranged (or added) comments at the start of each file, so the
# description is near the top and the changelog near the bottom.  Added
# Log: lines to get an automatically updated changelog from now on; I
# hope it works.
#
#
# older ChangeLog messages:
# 2001-09-06  Jerry Veldhuis, jerry@matilda.com
#	- started ChangeLog
#	- added/fixed some program qualifiers
#	- changed format of warning messages
#	- removed usage of unbroken_text setting in HTML::Parser
#	- fixed dumpMe() calls that don't print return value.
#	- reworked code to identify and drop schedule tables that
#	  don't parse correctly.
#	- when row in table missing columns, we attempt to print
#	  channel information for easier diagnosis.
#	- identifies when clicktv server responds with
#	  "Sorry, your request could not be processed", sleeps and
#	  tries again, eventually failing entire request.
#	- if directory ./urldata exists caches html pages to ease
#	  testing and problem diagnosis
#	- correctly identify year of movies
#	- auto corrects program details that look like 'actors' lists
#	  and then later notices these are on the unidentified
#	  qualifiers lists (because later, they were ruled-out as
#	  being properly identified)
#
# 2001-10-20  Jerry Veldhuis, jerry@matilda.com
#	- hacked to grab from tvguide.ca instead of clicktv.com
#	- program details etc are almost non-existant
#	- who knows how well this worked :)

#
# This package is the core scraper for schedules
# from clicktv.com and tvguide.ca.
#

# Outstanding limitations.
# - Clicktv may change their format and we play catch-up.
#
# - sometimes details that appear in () get by us. In these cases,
#   we emit a "warning: unidentified qualifier %s" to
#   STDERR. These may be qualifiers we don't yet understand, feel
#   free contribute the error message and I'll add them.
#
# - maybe we should have an option to convert names in () that appear
#   in the program description to be evaluated as names of special
#   guests. Sometime the description ends with "guest:.." or
#   "guest stars:..."
#
# - some error messages may go to stdout instead of stderr
#
# - sometimes actors names include nicknames in (), for instance:
#   (Kasan Butcher, Cynthia (Alex) Datcher)
#   this parses incorrectly, its more work, but we could identify these.
#
# Future
# - when scraping fails it's very hard to recreate the problem
#   especially if a day passes and the html is no longer, maybe
#   in these cases we should be saving state and inputs to
#   a file that can later be examined to determine what went
#   wrong. But... then again why plan for failure :)
#
# - add some comments, so perldoc works. Maybe later if we
#   make subpackages for Channel and Program objects.
#
# - could use time first table request takes and amount
#   of data it required to download to put up a fairly
#   accurate progress bar. Unlike explorer it does something.
#   May require using something other than LWP::Simple for 
#   urldata lookups. Note: look at scp, for a good example
#
# - could attempt to extract guest names from descriptions to
#   locate 'actors'. For instance, some listings include
#   phrases like:
#       'Scheduled: actors Darrell Hammond and Lauren Graham,
#        music guest Case.'
#       'From June: L.A. Lakers forward Rick Fox, music
#        guest Dido, actor Tim Stack.'
#       'From March: actor Dean Haglund; music guest Quartetto
#        Gelato; columnist George Christy; dog of the week.'
#   could probably pick out the 'actors' listed, maybe not
#   the 'musical guest...' and 'L.A. Lakeer forward...'
#   Although this is probably better suited for a secondary
#   xmltv output scraper.

use strict;
use HTML::Entities qw(decode_entities);

use vars qw(@ISA $infield $inrecord $intable $nextTableIsIt $VersionID);

$VersionID="ClickListings V0.2";

@ISA = qw(HTML::Parser);

require HTML::Parser;
use Dumpvalue;

my $debug=0;
my $verify=0;

sub reset($)
{
    my $self=shift;
    $self->{version}=$VersionID;

    delete($self->{Table});
    delete($self->{Row});
    delete($self->{Field});
    delete($self->{undefQualifiers});

    $infield=0;
    $inrecord=0;
    $intable=0;
    $nextTableIsIt=0;
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

sub start()
{
    my($self,$tag,$attr,$attrseq,$orig) = @_;

    # funny way of identifying the right table in the html, but this is
    # one of the only consistant ways.
    # - look for end of submit form and skip one table
    if ( $tag=~/^input$/io ) {
	if ( $attr->{type}=~/^submit$/io && 
	     $attr->{value}=~m/update grid/io ) {
	    # not next one, but the following... nice variable name :)
	    $nextTableIsIt=2;
	}
    }
    elsif ( $tag=~/^table$/io ) {
	$nextTableIsIt--;
	if ( $nextTableIsIt == 0 ) {
	    $self->{Table} = ();
	    $intable++;
	}
    }
    elsif ( $tag=~/^tr$/i ) {
	if ( $intable ) {
	    $self->{Row} = ();
	    $inrecord++ ;
	}
    }
    else {
	if ( $intable && $inrecord ) {
	    if ( $tag=~/^t[dh]$/io ) {
		$infield++;
	    }
	    if ( $infield ) {
		my $thing;

		$thing->{starttag}=$tag;
		if ( keys(%{$attr}) != 0 ) {
		    $thing->{attr}=$attr;
		}
		push(@{$self->{Field}->{things}}, $thing);
	    }
	}

    }
    if ( $debug>1 && $intable ) {
	print STDERR "start: ($tag, ".dumpMe($attr).")\n";
    }

}

sub text()
{
    my ($self,$text) = @_;

    if ( $intable && $inrecord && $infield ) {
	my $thing;
    
	$thing->{text}=$text;
	push(@{$self->{Field}->{things}}, $thing);

	#$self->{Field}->{text} .= $text;
    }
}

sub massageText
{
    my ($text) = @_;

    $text=~s/&nbsp;/ /og;
    $text=decode_entities($text);
    $text=~s/^\s+//o;
    $text=~s/\s+$//o;
    $text=~s/\s+/ /o;
    return($text);
}

#
# Don't want to complain how annoying it was to hunt down some
# of the ratings things here, ends up to be hit and miss scraping
# a couple of pages and see what details don't get evaluated, then
# try and determine where they might fit.
# 
sub evaluateDetails
{
    my ($undefQualifiers, $result, @parenlist)=@_;

    for my $info (@parenlist) {
	print STDERR "Working on details: $info\n" if ( $debug );

	# special cases, if Info starts with Director, its a list.
	if ( $info=~s/^Director: //oi ) {
	    if ( defined($result->{prog_director}) ) {
		$result->{prog_director}.=",";
	    }
	    $result->{prog_director}.=$info;
	    next;
	}
	# check for (1997) being the year declaration
	elsif ( $info=~s/^(\d+)$/$1/o ) {
	    $result->{prog_year}=$info;
	    next;
	}
	elsif ( $info=~m/^\s*\.\s*$/o ) {
	    # ignore left over from sentence endings
	    next;
	}
	# check for duration (ie '(6 hr) or (2 hr 30 min)')
	elsif ($info=~s/^[0-9]+\s*hr$//oi ) {
	    # ignore
	    next;
	}
	elsif ($info =~s/^[0-9]+\s*hr\s*[0-9]+\s*min$//oi ) {
	    # ignore
	    next;
	}

	my $matches=0;
	my @unmatched;

	for my $i (split(/,/,$info)) {

	    $i=~s/^\s+//og;
	    $i=~s/\s+$//og;
	    print STDERR "\t checking detail: $i\n" if ( $debug > 2 );
	
	    #
	    # www.tvguidelines.org and http://www.fcc.gov/vchip/
	    if ( $i=~m/^TV-(Y)$/oi ||
		 $i=~m/^TV-(Y7)$/oi ||
		 $i=~m/^TV-(G)$/oi ||
		 $i=~m/^TV-(PG)$/oi ||
		 $i=~m/^TV-(14)$/oi ||
		 $i=~m/^TV-(MA)$/oi ) {
		$result->{prog_ratings_VCHIP}="$1";
		undef($i);
		$matches++;
		next;
	    }

	    # Expanded VChip Ratings (see notes above)
	    if ( $i=~m/^FV$/oi ) {
		$result->{prog_ratings_VCHIP_Expanded}="Fantasy Violence";
		undef($i);
		$matches++;
		next;
	    }
	    elsif ($i=~m/^V$/oi ) {
		$result->{prog_ratings_VCHIP_Expanded}="Violence";
		undef($i);
		$matches++;
		next;
	    }
	    elsif ($i=~m/^S$/oi ) {
		$result->{prog_ratings_VCHIP_Expanded}="Sexual Situations";
		undef($i);
		$matches++;
		next;
	    }
	    elsif ($i=~m/^L$/oi ) {
		$result->{prog_ratings_VCHIP_Expanded}="Course Language";
		undef($i);
		$matches++;
		next;
	    }
	    elsif ($i=~m/^D$/oi ) {
		$result->{prog_ratings_VCHIP_Expanded}="Suggestive Dialogue";
		undef($i);
		$matches++;
		next;
	    }

	    # www.filmratings.com
	    if ( $i=~m/^(G)$/oi ||
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
		$result->{prog_ratings_MPAA}="$1";
		undef($i);
		$matches++;
		next;
	    }
	    elsif ($i=~m/^(GP)$/oi || # french for PG
		   $i=~m/^(GP-13)$/oi || # french for PG-13
		   $i=~m/^Rated (GP)$/oi || # french for PG
		   $i=~m/^Rated (GP-13)$/oi # french for PG-13
		   ) {
		# convert back from french
		my $rating=$1;
		$rating=~s/^GP/PG/og;
		$result->{prog_ratings_MPAA}="$rating";
		undef($i);
		$matches++;
		next;
	    }

	    # search for 'violence' at www.twckc.com and get:
	    #    http://www.twckc.com/inside/faq2_0116.html
	    # 
	    if ( $i=~m/^(Adult Content)$/oi ||
		 $i=~m/^(Adult Humor)$/oi ||
		 $i=~m/^(Adult Language)$/oi ||
		 $i=~m/^(Adult Situations)$/oi ||
		 $i=~m/^(Adult Theme)$/oi ||
		 $i=~m/^(Brief Nudity)$/oi ||
		 $i=~m/^(Graphic Language)$/oi ||
		 $i=~m/^(Graphic Violence)$/oi ||
		 $i=~m/^(Mature Theme)$/oi ||
		 $i=~m/^(Mild Violence)$/oi ||
		 $i=~m/^(Nudity)$/oi ||
		 $i=~m/^(Profanity)$/oi ||
		 $i=~m/^(Strong Sexual Content)$/oi ||
		 $i=~m/^(Rape)$/oi ||
		 $i=~m/^(Violence)$/oi ) {
		push(@{$result->{prog_ratings_Warnings}}, $1);
		undef($i);
		$matches++;
		next;
	    }

	    if ( $i=~m/^debut$/oi || 
		 $i=~m/^d.but$/oi # french translation e usually has circumflex (sp?)
		 ) {
		 $result->{prog_qualifiers}->{Debut}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^in progress$/oi ) {
		$result->{prog_qualifiers}->{InProgress}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^finale$/oi ||
		    $i=~m/^series finale$/oi ||
		    $i=~m/^season finale$/oi) {
		$result->{prog_qualifiers}->{LastShowing}=$i;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^premiere$/oi ||
		    $i=~m/^series premiere$/oi ||
		    $i=~m/^season premiere$/oi ||
		    $i=~m/^D.but de la s.rie$/oi # french
		    ) {
		$result->{prog_qualifiers}->{PremiereShowing}=$i;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^network\-/oi ) {
		# understand and ignore these
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^closed captioned$/oi ||
		    # french translation
		    # loosly translates to 'Subtitled coded for the deaf people'
		    $i=~m/^Sous-titr. cod. pour les malentendants$/oi
		    ) {
		$result->{prog_qualifiers}->{ClosedCaptioned}++;
		undef($i);
		$matches++;
		next;
	    }
	    # this pops up for series oriented showings
	    elsif ( $i=~m/^part ([0-9]+) of ([0-9]+)$/oi ||
		    $i=~m/^partie ([0-9]+) de ([0-9]+)$/oi # french translation
		    ) {
		$result->{prog_qualifiers}->{PartInfo}="Part $1 of $2";
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^HDTV$/oi ) {
		$result->{prog_qualifiers}->{HDTV}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^Taped$/oi ||
		    $i=~m/^Same-day Tape$/oi ) {
		$result->{prog_qualifiers}->{Taped}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^Dubbed$/oi ) {
		$result->{prog_qualifiers}->{Dubbed}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^new$/oi ) {
		# ignore
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^live$/oi ||
		    $i=~m/^live phone-in$/oi) {
		$result->{prog_qualifiers}->{Live}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^Subject to Blackout$/oi ) {
		# understand, but ignore
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^Time approximate$/oi ) {
		# understand, but ignore
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^repeat$/oi ) {
		# understand, but ignore
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^cable in the classroom$/oi ) {
		# understand, but ignore
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^joined in progress$/oi ) {
		# understand, but ignore
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^subtitled$/oi ) {
		$result->{prog_qualifiers}->{Subtitles}++;
		undef($i);
		$matches++;
		next;
	    }
	    elsif ( $i=~m/^in stereo$/oi ) {
		$result->{prog_qualifiers}->{InStereo}++;
		undef($i);
		$matches++;
		next;
	    }
	    # saw an instance of "In German" appear
	    elsif ( $i=~m/^in (.*)$/oi ) {
		$result->{prog_qualifiers}->{Language}="$1";
		undef($i);
		$matches++;
		next;
	    }
	    # appears in details window
	    elsif ( $i=~m/^paid program$/oi ) {
		$result->{prog_qualifiers}->{PaidProgram}++;
		undef($i);
		$matches++;
		next;
	    }
	    # appears in details window
	    elsif ( $i=~m/^animated$/oi ) {
		$result->{prog_qualifiers}->{Animated}++;
		undef($i);
		$matches++;
		next;
	    }
	    # appears in details window
	    elsif ( $i=~m/^black & white$/oi ) {
		$result->{prog_qualifiers}->{BlackAndWhite}++;
		undef($i);
		$matches++;
		next;
	    }
	    # appears in details window
	    elsif ( $i=~m/^home video$/oi ) {
		# understand, but ignore
		undef($i);
		$matches++;
		next;
	    }

	    if ( defined($i) && length($i) ) {
		warn "Failed to decode info: \"$i\"\n" if ( $debug );
		push(@unmatched, $i);
	    }
	}

	if ( @unmatched ) {
	    # if nothing inside the () matched any of the above,
	    if ( $matches == 0 ) {
		my $found=0;
		for my $k (@unmatched) {
		    if ( defined($undefQualifiers->{$k}) ) {
			$found++;
		    }
		}

		# assume anything else is a list of actors or something to complain about
		if ( $found == 0 &&
		     (!defined($result->{prog_actors}) || scalar(@{$result->{prog_actors}}) == 0) ) {
		    #print STDERR "Actors ?: ". join(",", @unmatched)."\n";
		    push(@{$result->{prog_actors}}, @unmatched);
		}
		else {
		    if ( $found == scalar(@unmatched) ) {
			# all unmatched keywords are in knownUndefined, so ignore
		    }
		    else {
			if ( $found != 0 ) {
			    warn "undefined qualifier(s) (or actor list may be corrupt) $info\n";
			}
			else {
			    # add unfound keywords to the list of known undefined keywords.
			    for my $k (@unmatched) {
				if ( !defined($undefQualifiers->{$k}) ) {
				    $undefQualifiers->{$k}=1;
 				    warn "warning: unidentified qualifier '$k'\n";
				}
				else {
				    $undefQualifiers->{$k}++;
				}
			    }
			}
		    }
		}
	    }
	    # if one thing in the () matched, but not others, complain they
	    # don't appear in our list of known details
	    else {
		for my $k (@unmatched) {
		    if ( ! defined($undefQualifiers->{$k}) ) {
			$undefQualifiers->{$k}=1;
			warn "warning: unidentified qualifier \"$k\"\n";
		    }
		    else {
			$undefQualifiers->{$k}++;
		    }
		}
	    }
	}
    }
    return($result);
}

sub endField($)
{
    my ($self) = @_;
    my $result;
    my $mycolumn=(defined($self->{Row}))?scalar(@{$self->{Row}}):0;
    my $myrow=(defined($self->{Table}))?scalar(@{$self->{Table}}):0;
    
    #print STDERR "push field: \n";

    #$result->{prog_title}='';

    # save cell things for later
    #$result->{cellThings}=@{$self->{Field}->{things}};

    my @thgs=@{$self->{Field}->{things}};

    if ( $debug ) {
	my $count=0;
	foreach my $entry (@thgs) {
	    print STDERR "\tPRE $count".dumpMe($entry)."\n";
	    $count++;
	}
    }

    #first colum is always for channels
    if ( 0 && $mycolumn == 0 ) {
	if ( $thgs[0]->{starttag}=~/^td$/io &&
	     $thgs[1]->{starttag}=~/^font$/io &&
	     defined($thgs[2]->{text}) &&
	     $thgs[3]->{starttag}=~/^font$/io &&
	     $thgs[4]->{text} eq '(' &&
	     $thgs[5]->{starttag}=~/^a$/io &&
	     defined($thgs[6]->{text}) ) {
	}
    }

    if ( $verify ) {
	my $str="";

	foreach my $e (@thgs) {
	    my $understood=0;
	    if ( defined($e->{starttag}) ) {
		if ( $e->{starttag}=~/^img$/io ) {
		    $understood++;
		    if ( $e->{attr}->{src}=~m;^../images/tvguide/arrow-left.gif;io ) {
			# ignore
		    }
		    elsif ( $e->{attr}->{src}=~m;^../images/tvguide/arrow-right.gif;io ) {
			# ignore
		    }
		    elsif ( $e->{attr}->{src}=~m/_prev/oi ) {
			$str.="<cont-prev>";
		    }
		    elsif ( $e->{attr}->{src}=~m/_next/oi ) {
			$str.="<cont-next>";
		    }
		    elsif ( $e->{attr}->{src}=~m/\/stars/oi ) {
			$str.="<star rating>";
		    }
		    else {
			die "unable to identify img '". keys (%{$e}) ."'";
		    }
		}
		else {
		    $str.="<$e->{starttag}>";
		    $understood++;
		}
		if ( defined($e->{attr}) ) {
		    $understood++;
		}
	    }
	    if ( defined($e->{endtag}) ) {
		$str.="</".$e->{endtag}.">";
		$understood++;
	    }
	    if ( defined($e->{text}) ) {
		$understood++;
		if ( $e->{text}=~m/^\s*\(\*+\)$/o ) {
		    $str.="<star rating>";
		}
		elsif ( $e->{text}=~m/^\s+$/o ) {
		    $str.="space";
		} 
		else {
		    $str.="text";
		}
	    }
	    if ( keys (%{$e}) != $understood ) {
		warn "understood $understood, out of ".keys (%{$e}) ." keys of:".dumpMe($e)."\n";
	    }
	}
	print STDERR "PROG SYNTAX: $str\n";
    }

    # cells always start with 'td' and end in 'td'

    for (my $e=0 ; $e<scalar(@thgs) ; $e++) {
	my $thg0=$thgs[$e];
	if ( defined($thg0->{starttag}) && $thg0->{starttag}=~/^img$/io ) {
	    if ( defined($thg0->{attr}->{src}) ) {
		if ( $thg0->{attr}->{src}=~m;^../images/tvguide/arrow-left.gif;io) {
		    # ignore
		    next;
		}
		elsif ( $thg0->{attr}->{src}=~m;^../images/tvguide/arrow-right.gif;io ) {
		    # ignore
		    next;
		}
		elsif ( $thg0->{attr}->{src}=~m/_prev/oi ) {
		    #print STDERR "entry was cont from prior listing\n";
		    $result->{contFromPreviousListing}=1;

		    if ( $thgs[$e-1]->{starttag}=~/^a$/io &&
			 $thgs[$e+1]->{endtag}=~/^a$/io ) {
			
			# next entry should be line contains time it ends
			if ( $thgs[$e+2]->{text}=~s/^[0-9]+:[0-9]+[ap]m\s+//oi ) {
			    if ( $thgs[$e+2]->{text}=~m/^\s+$/o ) {
				splice(@thgs,$e-1,4);
			    }
			    else {
				splice(@thgs,$e-1,3);
			    }
			    $e=( $e <= 2 )?0:$e-2;
			    next;
			}
			die "failed to find time <text> tag for previous start time";
		    }
		    die "found prev line without <a></a> around";
		}
		elsif ($thg0->{attr}->{src}=~m/_next/oi ) {
		    #print STDERR "entry was cont to next listing\n";
		    $result->{contToNextListing}=1;
		    
		    if ( $thgs[$e-1]->{starttag}=~/^a$/io &&
			 $thgs[$e+1]->{endtag}=~/^a$/io ) {
			splice(@thgs,$e-1,3);
			$e=( $e <= 2 )?0:$e-2;
			next;
		    }
		    die "failed to find time <text> tag for previous start time";
		}
		elsif ($thg0->{attr}->{src}=~m/\/stars_(\d+)\./oi ) {
		    $result->{prog_stars_rating}=sprintf("%.1f", int($1)/2);
		    if ( $thgs[$e-1]->{text}=~m/^\s+$/o ) {
			splice(@thgs,$e-1,2);
			$e-=2;
		    }
		    else {
			splice(@thgs,$e,1);
			$e--;
		    }
		    next;
		}
		else {
		    warn "warning: img link defined with unknown image link ".$thg0->{attr}->{src}."\n";
		    next;
		}
		warn "img link defined with unknown image link ".$thg0->{attr}->{src}."\n";
		exit(1);
	    }
	    warn "img link defined without src definition $e ".$thg0."\n";
	    print STDERR dumpMe($thg0)."\n";
	    exit(1);
	}

	# catch star ratings given as '(***)'
	# and <font> (***)</font> means text is the description
	if ( scalar(@thgs)>$e+2 &&
	     defined($thg0->{starttag}) && $thg0->{starttag}=~/^font$/io &&
	     defined($thgs[$e+1]->{text}) && $thgs[$e+1]->{text}=~m/^\s*\(\*+\)$/o &&
	     defined($thgs[$e+2]->{endtag}) && $thgs[$e+2]->{endtag}=~/^font$/io ) {
	    $thgs[$e+1]->{text}=~m/^\s*\((\*+)\)$/o;
	    $result->{prog_stars_rating}=sprintf("%.1f", length($1));
	    splice(@thgs,$e,3);
	    $e--;
	    # start again
	    next;
	}

	if ( defined($thg0->{text}) && $thg0->{text}=~m/^\s*\((\*+)\)$/o ) {
	    $result->{prog_stars_rating}=sprintf("%.1f", length($1));
	    splice(@thgs,$e,1);
	    
	    # start again
	    $e--;
	    next;
	}
	
	# nuke <b> and </b>
	if ( (defined($thg0->{starttag}) && $thg0->{starttag}=~/^b$/io) ||
	     (defined($thg0->{endtag}) && $thg0->{endtag}=~/^b$/io)) {
	    splice(@thgs,$e,1);
	    
	    # start again
	    $e--;
	    next;
	}
	
	# grab space<i>text</i>space and remove surrounding space
	if ( scalar(@thgs)>$e+4 &&
	     defined($thg0->{text}) && $thg0->{text}=~m/^\s+$/o &&
	     defined($thgs[$e+1]->{starttag}) && $thgs[$e+1]->{starttag}=~/^i$/io &&
	     defined($thgs[$e+2]->{text}) &&
	     defined($thgs[$e+3]->{endtag}) && $thgs[$e+3]->{endtag}=~/^i$/io &&
	     defined($thgs[$e+4]->{text}) && $thgs[$e+4]->{text}=~m/^\s+$/o ) {
	    $result->{prog_subtitle}=$thgs[$e+2]->{text};
	    # remove space entries
	    splice(@thgs,$e,5);
	    #splice(@thgs,$e+3,1);
	    
	    # start again
	    $e--;
	    next;
	}

	# grab <i>text</i> as being the subtitle
	if ( scalar(@thgs)>$e+2 &&
	     defined($thg0->{starttag}) && $thg0->{starttag}=~/^i$/io &&
	     defined($thgs[$e+1]->{text}) &&
	     defined($thgs[$e+2]->{endtag}) && $thgs[$e+2]->{endtag}=~/^i$/io) {
	    $result->{prog_subtitle}=massageText($thgs[$e+1]->{text});
	    splice(@thgs,$e,3);
	    
	    # start again
	    $e--;
	    next;
	}
	# and <font>text</font> in column 1 of tables means affiliate station
	# (also <font>(<a>text</a>)</font>)
	# here, so we put it in the description
	if ( $mycolumn==1 ) {
	    if ( scalar(@thgs)>$e+2 &&
		 defined($thg0->{starttag}) && $thg0->{starttag}=~/^font$/io &&
		 defined($thgs[$e+1]->{text}) &&
		 defined($thgs[$e+2]->{endtag}) && $thgs[$e+2]->{endtag}=~/^font$/io ) {
		$result->{prog_desc}=massageText($thgs[$e+1]->{text});
		splice(@thgs,$e,3);
		$e--;
		# start again
		next;
	    }
	    if ( scalar(@thgs)>$e+6 &&
		 defined($thg0->{starttag}) && $thg0->{starttag}=~/^font$/io &&
		 defined($thgs[$e+1]->{text}) && $thgs[$e+1]->{text} eq "(" &&
		 defined($thgs[$e+2]->{starttag}) && $thgs[$e+2]->{starttag}=~/^a$/io &&
		 defined($thgs[$e+3]->{text}) && 
		 defined($thgs[$e+4]->{endtag}) && $thgs[$e+4]->{endtag}=~/^a$/io &&
		 defined($thgs[$e+5]->{text}) && $thgs[$e+5]->{text} eq ")" &&
		 defined($thgs[$e+6]->{endtag}) && $thgs[$e+6]->{endtag}=~/^font$/io ) {
		$result->{prog_desc}=massageText($thgs[$e+3]->{text});
		splice(@thgs,$e,7);
		$e--;
		# start again
		next;
	    }
	}

	# grab <font><br> means no description was given
	# and <font>textspace<br> means text is the description
	# and <font>text<br> means text is the description
	# also check </font> combination
	if ( (defined($thg0->{starttag}) && $thg0->{starttag}=~/^font$/io) ||
	     (defined($thg0->{endtag}) && $thg0->{endtag}=~/^font$/io) ) {
	    if ( 0 && defined($thgs[$e+1]->{starttag}) && $thgs[$e+1]->{starttag}=~/^br$/io) {
		$result->{prog_desc}="";
		splice(@thgs,$e+1,1);
		# start again
		$e--;
		next;
	    }
	    elsif ( scalar(@thgs)>$e+2 && 
		    defined($thgs[$e+1]->{text}) &&
		    defined($thgs[$e+2]->{starttag}) && $thgs[$e+2]->{starttag}=~/^br$/io) {
		$result->{prog_desc}=massageText($thgs[$e+1]->{text});
		splice(@thgs,$e+1,2);
		# start again
		$e--;
		next;
	    }
	    elsif ( scalar(@thgs)>$e+2 && 
		    defined($thgs[$e+1]->{text}) &&
		    defined($thgs[$e+2]->{text}) &&
		    defined($thgs[$e+3]->{starttag}) && $thgs[$e+3]->{starttag}=~/^br$/io) {
		$result->{prog_desc}=massageText($thgs[$e+1]->{text}.$thgs[$e+2]->{text});
		splice(@thgs,$e+1,3);
		# start again
		$e--;
		next;
	    }
	}
    }

    if ( $verify ) {
	my $str="";

	foreach my $e (@thgs) {
	    my $understood=0;
	    if ( defined($e->{starttag}) ) {
		$str.="<$e->{starttag}>";
		$understood++;
		if ( defined($e->{attr}) ) {
		    $understood++;
		}
	    }
	    if ( defined($e->{endtag}) ) {
		$str.="</".$e->{endtag}.">";
		$understood++;
	    }
	    if ( defined($e->{text}) ) {
		$understood++;
		if ( $e->{text}=~m/^\s*\(\*+\)$/o ) {
		    $str.="<star rating>";
		}
		elsif ( $e->{text}=~m/^\s+$/o ) {
		    $str.="space";
		} 
		else {
		    $str.="text";
		}
	    }
	    if ( keys (%{$e}) != $understood ) {
		warn "understood $understood, out of ".keys (%{$e}) ." keys of:";
		print STDERR dumpMe($e)."\n";
	    }
	}
	print STDERR "PROG2 SYNTAX: $str\n";
    }

    my $startEndTagCount=0;
    my @textSections;
    my $count=-1;
    foreach my $entry (@thgs) {
	$count++;

	if ( $debug > 1) { print STDERR "\tNUM $count".dumpMe($entry)."\n"; }

	#print STDERR "entry is a ". $entry ."\n";
	#print STDERR "entry start is a ". $entry->{starttag} ."\n" if ( defined($entry->{starttag}) );

	if ( defined($entry->{starttag}) ) {
	    my $tag=$entry->{starttag};

	    #print STDERR "tag is a ". $tag ."\n";

	    if ( $tag=~/^t[dh]$/io ) {
		if ( !defined($result->{fieldtag}) ) {
		    $result->{fieldtag}=$tag;
		}
		if ( defined($entry->{attr}->{colspan}) ) {
		    $result->{colspan}=$entry->{attr}->{colspan};
		}
		else {
		    $result->{colspan}=1;
		}
	    }
	    elsif ( $tag=~/^a$/io ) {
		die "link missing href attr" if ( !defined($entry->{attr}->{href}) );
		$result->{prog_href}=$entry->{attr}->{href};
	    }
	    elsif ( $tag=~/^[ib\!]$/io ) {
		# ignore
	    }
	    elsif ( $tag=~/^font$/io ) {
		$startEndTagCount++;
	    }
	    elsif ( $tag=~/^br$/io) {
		# ignore
	    }
	    elsif ( $tag=~/^nobr$/io) {
		# ignore
	    }
	    elsif ( $tag=~/^img$/io) {
		# ignore
	    }
	    else {
		warn "ignoring start tag: $tag\n";
	    }
	}
	elsif ( defined($entry->{endtag}) ) {
	    $startEndTagCount++;
	    my $tag=$entry->{endtag};
	    if ($tag=~/^a$/io) {
		#if ( !length($result->{prog_title}) ) {
		#   die "program missing a name";
		#}
		$startEndTagCount++;
	    }
	    elsif ( $tag=~/^font$/io ) {
		$startEndTagCount++;
	    }
	    elsif ( $tag=~/^t[dh]$/io) {
		# ignore
	    }
	    elsif ( $tag=~/^[ib\!]$/io ) {
		# ignore
	    }
	    elsif ( $tag=~/^nobr$/io) {
		# ignore
	    }
	    else {
		warn "ignoring end tag: $tag\n";
	    }
	}
	elsif ( defined($entry->{text}) ) {
		$textSections[$startEndTagCount].=$entry->{text};
	}
	else {
	    warn "undefined thing:$count:".dumpMe($entry)."\n";
	    die "undefined thing";
	}
    }

    my $extraDetails;
    for my $text (@textSections) {
	next if ( !defined($text) );

	$text=massageText($text);
	if ( $text=~m/^\(/o && $text=~m/\)$/o ) {
	    if ( defined($extraDetails) ) {
		$extraDetails.=" ";
	    }
	    $extraDetails.=$text;
	    next;
	}
	if ( !defined($result->{prog_title}) ) {
	    $result->{prog_title}=$text;
	}
	#elsif ( !defined($result->{prog_subtitle}) ) {
	#    $result->{prog_subtitle}=$text;
	#}
	elsif ( !defined($result->{prog_desc}) ) {
	    $result->{prog_desc}=$text;
	}
	elsif ( !defined($result->{prog_details}) ) {
	    $result->{prog_details}=$text;
	}
	else {
	    warn "don't have a place for extra text section '$text'\n";
	}
    }
    if ( defined($result->{prog_desc}) ) {
	my $desc=$result->{prog_desc};
	#print STDERR "checking $desc\n";
	if ( $desc=~m/\s*(\(\d\d\d\d\))[\s\.]*(.*)$/o ) {
	    if ( defined($extraDetails) ) {
		$extraDetails.=" ";
	    }
	    $extraDetails.="($1) $2";
	    $desc=~s/\s*\(\d\d\d\d\).*$//o;
	}
	while ($desc=~m/(\([^\)]+)\)[\s\.]*$/o ) {
	    my $detail=$1;
	    #print STDERR "found=$detail desc=$desc\n";
	    if ( defined($extraDetails) ) {
		$extraDetails.=" ";
	    }
	    $extraDetails.="$detail";
	    $desc=~s/\s*\([^\)]+\)[\s\.]*$//o;
	}
	if ( $desc=~m/\s*(\(\d\d\d\d\))[\s\.]*(.*)$/o ) {
	    if ( defined($extraDetails) ) {
		$extraDetails.=" ";
	    }
	    $extraDetails.="($1) $2";
	    $desc=~s/\s*\(\d\d\d\d\).*$//o;
	}
	$result->{prog_desc}=$desc;
    }

    if ( defined($extraDetails) ) {
	 if ( defined($result->{prog_details}) ) {
	     $result->{prog_details}="$extraDetails $result->{prog_details}";
	 }
	 else {
	     $result->{prog_details}="$extraDetails";
	 }
    }

    if ( defined($result->{prog_details}) ) {
	my $info=$result->{prog_details};

	my @parenlist=grep (!/^\s*$/, split(/(?:\(|\))/,$info));
	if ( scalar(@parenlist) ) {
	    evaluateDetails($self->{undefQualifiers}, $result, @parenlist);
	}
	delete($result->{prog_details});
    }

    # compress result removing unneeded entries or entries that have no values
    foreach my $key (keys %{$result}) {
	if ( length($result->{$key}) == 0 ) {
	    delete $result->{$key};
	}
    }

    if ( $debug ) {
	print STDERR "READ FIELD (row $myrow, col $mycolumn):".dumpMe($result)."\n";
    }

    push(@{$self->{Row}}, $result);

    #print STDERR "push field: $self->{Field}->{text} ($self->{Field}->{tag}, $self->{Field}->{colspan})\n";
    delete($self->{Field});
}

sub end()
{
    my ($self,$tag) = @_;

    if ( $tag=~/^table$/io ) {
	if ( $intable ) {
	    $intable--;
	}
    }
    elsif ( $tag=~/^t[dh]$/io ) {
	if ( $infield ) {
	    $infield--;
	    my $thing;
	    
	    $thing->{endtag}=$tag;
	    push(@{$self->{Field}->{things}}, $thing);

	    $self->endField($tag);
	}
    }
    elsif ( $tag=~/^tr$/io ) {
	if ( $inrecord ) {
	    $inrecord--;
	    push @{$self->{Table}},\@{$self->{Row}};
	    undef($self->{Row});
	}
    }
    else {
	if ( $intable && $inrecord && $infield ) {
	    my $thing;
    
	    $thing->{endtag}=$tag;
	    push(@{$self->{Field}->{things}}, $thing);
	}
    }
}

package ClickListings;

#
# an attempt to read multple listing tables and merge them.
# we merge the rows, then will attempt to collaps the
# cells that spanned listing pages.
#

use strict;
use LWP::Simple;
use DB_File;

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

sub new {
    my($type) = shift;
    my $self={ @_ };            # remaining args become attributes
    
    die "no ServiceID specified in create" if ( ! defined($self->{ServiceID}) );
    die "no URLBase specified in create" if ( ! defined($self->{URLBase}) );
    die "no DetailURLBase specified in create" if ( ! defined($self->{DetailURLBase}) );
    die "no undefQualifiers specified in create" if ( ! defined($self->{undefQualifiers}) );

    # do we trust all details in 'details' pages ?
    # For some reason the grid details are more accurate than
    # in the details page
    $self->{TrustAllDetailsEntries}=0;

    bless($self, $type);

    return($self);
}

sub getListingURLData($$)
{
    my $self=shift;
    return(LWP::Simple::get($_[0]));
}

sub getListingURL($$$$$)
{
    my $self=shift;
    my ($hour, $day, $month, $year)=@_;

    return("$self->{URLBase}?$self->{ServiceID}&startDay=${month}/${day}/${year}&startTime=$hour");
    #return("$self->{URLBase}?$self->{ServiceID}&gDate=${month}A${day}A${year}&gHour=$hour");
}

sub getDetailURL($$)
{
    my $self=shift;
    return("$self->{DetailURLBase}?$self->{ServiceID}&prog_ref=$_[0]");
}

sub getDetailURLData($$)
{
    my $self=shift;
    return(LWP::Simple::get($_[0]));
}

# used for testing/debugging
sub storeListing
{
    my ($self, $filename)=@_;

    if ( ! open(FILE, "> $filename") ) {
	warn "$filename: $!";
	return(0);
    }
    my %hash;

    $hash{TimeZone}=$self->{TimeZone} if ( defined($self->{TimeZone}) );
    $hash{TimeLine}=$self->{TimeLine} if ( defined($self->{TimeLine}) );
    $hash{Channels}=$self->{Channels} if ( defined($self->{Channels}) );
    $hash{Schedule}=$self->{Schedule} if ( defined($self->{Schedule}) );
    $hash{Programs}=$self->{Programs} if ( defined($self->{Programs}) );
    
    my $d=new Data::Dumper([\%hash], ['*hash']);
    $d->Purity(0);
    $d->Indent(1);
    print FILE $d->Dump();
    close FILE;
    return(1);
}

# used for testing/debugging
sub restoreListing
{
    my ($self, $filename)=@_;

    if ( ! open(FILE, "< $filename") ) {
	warn "$filename: $!";
	return(0);
    }
    my %hash;

    my $saveit=$/;
    undef $/;

    eval {<FILE>};
    if ($@) {
	$/=$saveit;
	warn "failed to read $filename: $@\n";
	close(FILE);
	return(1);
    }
    $/=$saveit;
    close FILE;

    $self->{TimeZone}=$hash{TimeZone} if ( defined($hash{TimeZone}) );
    $self->{TimeLine}=$hash{TimeLine} if ( defined($hash{TimeLine}) );
    $self->{Channels}=$hash{Channels} if ( defined($hash{Channels}) );
    $self->{Schedule}=$hash{Schedule} if ( defined($hash{Schedule}) );
    $self->{Programs}=$hash{Programs} if ( defined($hash{Programs}) );
    return(1);
}

# determine if this row in the table is
# a replicated "time" row.
sub isTimeRow
{
    my @row=@{$_[0]};

    for (my $col=1 ; $col < scalar(@row)-1 ; $col++ ) {
	my $field=$row[$col];
	
	if ( !($field->{fieldtag}=~/^th$/io) ) {
	    return(0);
	}
	if ( defined($field->{prog_title}) ) {
	    if ( !($field->{prog_title}=~m/^[0-9]+:[03]0 [ap]\.m\.$/o) &&
		 !($field->{prog_title}=~m/^[0-9]+:[03]0[AP]M$/o) ) {
		return(0);
	    }
	}
    }
    return(1);
}

sub isAdvertisement
{
    my @row=@{$_[0]};

    my $field=$row[1];
    if ( defined($field->{starttag}) && $field->{starttag}=~/^iframe$/io ) {
	return(1);
    }
    return(0);
}

# internal check 
# currently unimplemented since I don't think we need it.
sub verifyProgramMatches($$)
{
    my ($prog, $savedprog)=@_;
    #die "unimplemented\n";
}

use Date::Manip;

sub readSchedule
{
    my $self=shift;
    my (@timedefs) = @_;

    my @WholeTable;
    my @TimeLine;

    if ( defined($self->{Schedule}) ) {
	@WholeTable=@{$self->{Schedule}};
    }
    if ( defined($self->{TimeLine}) ) {
	@TimeLine=@{$self->{TimeLine}};
    }

    my $hours_per_listing=0;
    my $dataFormat;

    my $first=1;
    foreach my $timedef (@timedefs) {

	my ($hourMin, $hourMax, $nday, $nyear)=(@{$timedef});

	my @TimeTable;
	my $SegmentsInTimeLine=-1;
	my $DayOfSchedules;
	my $Schedules=0;

	for (my $wanthour=$hourMin; $wanthour<$hourMax ; $wanthour+=$hours_per_listing) {
	    my $scheduleCorrupt=0;
	    my $hour=$wanthour;
	    if ( $hour == 24 ) {
		$hour=0;
		$nday++;
	    }
	    my ($year,$month,$day,$hr,$min,$sec)=Date::Manip::Date_NthDayOfYear($nyear, $nday);

	    my $url=$self->getListingURL($hour, $day, $month, $year);
	    printf STDERR "retrieving hour $hour of %4d-%02d-%02d...\n", $year, $month, $day;
	    printf STDERR "url=$url\n" if ($debug);
	    
	    my $tbl = new ClickListings::ParseTable();
	    $tbl->reset();
	    $tbl->{undefQualifiers}=$self->{undefQualifiers};

	    #print "url:$url\n";
	    my $urldata;

	    my $attemptDelay=10;
	    while ( !defined($urldata) ) {
		if ( -d "urldata" ) {
		    if ( open(FD, "< urldata/$hour-$year-$month-$day.html") ) {
			my $r=$/;
			undef($/);
			$urldata=<FD>;
			close(FD);
			$/=$r;
		    }
		}
		
		if ( !defined($urldata) ) {
		    $urldata=$self->getListingURLData($url);
		}

		if ( !defined($urldata) ) {
		    warn "unable to read url $url\n";
		    return(0);
		}
		else {
		    print STDERR "\tread ".length($urldata). " bytes of html\n" if ( $debug );
		    print STDERR "urldata:\n'$urldata'\n" if ( $debug>1 );
		    if ( -d "urldata" ) {
			if ( open(FD, "> urldata/$hour-$year-$month-$day.html") ) {
			    print FD $urldata;
			    close(FD);
			}
		    }
		}

		if ( $urldata=~m/(Please enter a five digit U.S. ZIP code)/oi ) {
		    print STDERR "Server Response: $1..\n";
		    print STDERR "Update ServiceID in script, and try again\n";
		    return(0);
		}
		    
		if ( $urldata=~m/(Sorry, your request could not be processed)/oi ) {
		    print STDERR "Server Response: $1..\n";
		    # flush cache if enabled
		    if ( -f "urldata/$hour-$year-$month-$day.html" ) {
			unlink("urldata/$hour-$year-$month-$day.html");
		    }
		    if ( $attemptDelay > 30*100 ) {
			warn "failed too many times..giving up\n";
			return(0);
		    }
		    warn "sleeping $attemptDelay seconds and trying again..\n";
		    sleep($attemptDelay);
		    $attemptDelay+=30;
		    undef($urldata);
		}
	    }

	    # first listing, scrape for number of hours per page
	    if ( $first ) {
		$first=0;

		if ( $url=~m/www\.clicktv\.com/o ) {
		    $dataFormat="clicktv";
		}
		elsif ($url=~m/tvguidelive\.clicktv\.com/o ) {
		    $dataFormat="tvguidelive";
		}
		elsif ($url=~m/tvlistings\.tvguidelive\.com/o ) {
		    $dataFormat="tvguidelive";
		}
		else {
		    die "unknown data format from url:$url";
		}

		# hack - at tvguidelive, the channel number appears in the first column,
		# so here we copy it into the second
		if ( $dataFormat eq "tvguidelive" ) {
		    $urldata=~s;<b>(\d+)</b></font></td><td class='Station'><font size='(\d+)' >;<b>$1</b></font></td><td class='Station'><font size='$2' >$1 ;og;
		}

		# look for
		# <a href='gridlisting.asp?UID={5E9C238D-F399-4DA4-BEB1-52D3C7BA5776}&\
		#  StartDay=10/3/2001&StartTime=12&gChRef=&Page=0&CO=8200&ShowType='><img src='../images/tvguide/arrow-left.gif' border='0'></a>
		if ( !($urldata=~m/<a href=\'gridlisting.asp\?UID=[^&]+&StartDay=[^&]+&StartTime=([0-9]+)[^>]+><img src='..\/images\/tvguide\/arrow-right.gif'/i) ) {
		    warn "error: unable to determine number of hours in each listing\n";
		    print STDERR "urldata:\n$urldata\n";
		    return(0);
		}
		else {
		    my $next=$1;
		    print STDERR "next=$next, hour=$hour\n" if ( $debug );
		    if ( $hour > $next ) {
			$hours_per_listing=$next+24-$hour;
		    }
		    else {
			$hours_per_listing=$next-$hour;
		    }
		    print STDERR "user selected $hours_per_listing hours in each listing\n" if ( $debug );
		}

		if ( !($urldata=~m/<b>Lineup:<\/b>[^\|]+\|\s+([A-Z]+)&nbsp;/o) ) {
		    warn "error: time zone information missing from url source\n";
		    print STDERR "urldata:\n$urldata\n";
		    return(0);
		}
		if ( defined($self->{TimeZone}) && $self->{TimeZone} ne $1 ) {
		    warn "error: attempt to add listings from two different time zones\n";
		    print STDERR "       $self->{TimeZone} != $1\n";
		    return(0);
		}
		$self->{TimeZone}=$1;
		print STDERR "user selected $self->{TimeZone} as his time zone\n" if ( $debug );
	    }

	    print STDERR "parsing ..\n" if ($debug);
	    $tbl->parse($urldata);

	    my $tablearr=$tbl->{Table};
	    if ( !defined($tablearr) ) {
		warn "no tables found\n";
		print STDERR "urldata:\n$urldata\n";
		return(0);
	    }
	    
	    #my @tablearr=$tablearr[0];
	    
	    #print STDERR "RESULT:\n".dumpMe($tablearr)."\n/RESULT:\n";

	    my @noSubHeadersTable;
	    my @arr=@{$tablearr};

	    # for first row which is a 'time row' onto the array
	    push(@noSubHeadersTable, $arr[0]);

	    for (my $i=1 ; $i<scalar(@arr) ; $i++) {
		if ( isTimeRow(\@{$arr[$i]}) ) {
		    print STDERR "row $i is time\n" if ($debug);
		}
		elsif ( isAdvertisement(\@{$arr[$i]}) ) {
		    print STDERR "row $i is ad\n" if ($debug);
		}
		else {
		    push(@noSubHeadersTable, $arr[$i]);
		}
	    }
	
	    #print STDERR "Ended up with ". scalar(@noSubHeadersTable). " rows\n";

	    # traverse table, removing first un-usable columns
	    for (my $nrow=0 ; $nrow< scalar(@noSubHeadersTable) ; $nrow++) {
		my @row=@{$noSubHeadersTable[$nrow]};

		#print STDERR "examing row:".dumpMe(\@row)."\n";

		# remove unneeded last column
		if ( $nrow == 0 ) {
		    # check constraints on first column of time row
		    my $field=$row[0];
		    
		    if ( $field->{colspan} != 2 || !($field->{fieldtag}=~/^td$/io) || defined($field->{prog_title})) {
			print STDERR "ROW: ".dumpMe(\@{$noSubHeadersTable[$nrow]})."\n";
			print STDERR "FIELD: ".dumpMe($field)."\n";
			die "column 0 failed on row $nrow";
		    }
		    # change colspan to remove virtual first column
		    $field->{colspan}=1;
		}
		else {
		    # check constraints on first column of non-time rows
		    my $field=$row[0];
		    
		    if ( $field->{colspan} != 1 || !($field->{fieldtag}=~/^td$/io) || ($dataFormat eq "clicktv" && defined($field->{prog_title})) ) {
			print STDERR "ROW: ".dumpMe(\@{$noSubHeadersTable[$nrow]})."\n";
			print STDERR "FIELD: ".dumpMe($field)."\n";
			die "column 0 failed on row $nrow";
		    }
		    #print STDERR "row $nrow: deleting first column entry\n";
		    # remove the first column
		    splice(@{$noSubHeadersTable[$nrow]}, 0, 1);
		}
		
		# remove unneeded last column
		if ( 1 ) {
		    @row=@{$noSubHeadersTable[$nrow]};
		    my $field=$row[scalar(@{$noSubHeadersTable[$nrow]})-1];
		    
		    if ( $dataFormat eq "clicktv" && $nrow == 0 ) {
			# check constraints on last column of time row
			if ( $field->{colspan} != 2 || !($field->{fieldtag}=~/^td$/io) ) {
			    print STDERR "ROW: ".dumpMe(\@{$noSubHeadersTable[$nrow]})."\n";
			    print STDERR "FIELD: ".dumpMe($field)."\n";
			    die "column ".(scalar(@{$noSubHeadersTable[$nrow]})-1)." failed on row $nrow";
			}
			# change colspan to remove virtual last column
			$field->{colspan}=1;
		    }
		    else {
			# check constraints on last column of non-time rows
			if ( $field->{colspan} != 1 || !($field->{fieldtag}=~/^td$/io) ) {
			    print STDERR "ROW: ".dumpMe(\@{$noSubHeadersTable[$nrow]})."\n";
			    print STDERR "FIELD: ".dumpMe($field)."\n";
			    die "column ".(scalar(@{$noSubHeadersTable[$nrow]})-1)." failed on row $nrow";
			}
			#print STDERR "row $nrow: deleting last column entry ".(scalar(@{$noSubHeadersTable[$nrow]})-1)."\n";
			# remove the last column in the row
			splice(@{$noSubHeadersTable[$nrow]}, scalar(@{$noSubHeadersTable[$nrow]})-1, 1);
		    }
		}
		
		if ( $dataFormat eq "clicktv" ) {
		    # remove duplicated "first column" that appears in the last column that clicktv tables have
		    @row=@{$noSubHeadersTable[$nrow]};
		    my $col1=$row[0];
		    my $col2=$row[scalar(@{$noSubHeadersTable[$nrow]})-1];
		    
		    if ( $col1->{colspan}!=1 || !($col1->{fieldtag}=~/^td$/io) || 
			 (defined($col1->{prog_title}) != defined($col2->{prog_title}) || 
			  (defined($col1->{prog_title}) && $col1->{prog_title} ne $col2->{prog_title})) ) {
			print STDERR "ROW: ".dumpMe(\@{$noSubHeadersTable[$nrow]})."\n";
			print STDERR "FIELD1: ".dumpMe($col1)."\n";
			print STDERR "FIELD2: ".dumpMe($col2)."\n";
			die "first/last column failed to be duplicates - row $nrow";
		    }
		    #print STDERR "row $nrow: deleting last column entry ".(scalar(@{$noSubHeadersTable[$nrow]})-1)."\n";
		    splice(@{$noSubHeadersTable[$nrow]}, scalar(@{$noSubHeadersTable[$nrow]})-1, 1);
		}
	    }

	    # check/verify time row - which appears as first row
	    my @timerow=@{$noSubHeadersTable[0]};
	    splice(@timerow, 0, 1);

	    splice(@noSubHeadersTable, 0, 1);

	    # verify that first row contains the times
	    # then decode into a range of 30 minute segments
	    if ( 1 ) {
		# fix the first row of times to include the day/month/year
	    
		# ignore columns up until the one we just added
		my $field=$timerow[0];

		if ( !defined($field->{prog_title}) ) {
		    print STDERR "analyzing time cell:".dumpMe($field)."\n";
		    die "time cell failed to give value in 'prog_title'";
		}
		
		# get starting hour from first cell
		my $curhour;
		if ( $field->{prog_title}=~m/^(\d+):(\d+)\s*([ap])\.?m\.?$/iog ) {
		    my ($hour, $min, $am)=($1, $2, $3);
		    if ( $am=~/^a$/io ) { $hour=0 if ( $hour == 12 ); }
		    elsif ( $am=~/^p$/io ) { $hour+=12 if ( $hour!=12 );}
		    else { die "internal error how did we get '$am' ?"; }
		
		    if ( $min != 0 ) {
			die "internal error how did we start at a min $min ($field->{prog_title}) ?";
		    }
		    $curhour=$hour;
		}
		else {
		    die "no starting hour found in $field->{prog_title}";
		}
		
		# quick validation we have all segments 
		for (my $col=0 ; $col<scalar(@timerow) ; $col+=2, $curhour++) {
		    my $want1;
		    my $want2;
		    my $curday=$nday;
		
		    my $hourOfDay=$curhour;
		    if ( $curhour > 23 ) {
			$hourOfDay-=24;
			$curday++;
		    }

		    if ( $hourOfDay == 0  ) {
			$want1="12:00AM";
			$want2="12:30AM";
		    }
		    elsif ( $hourOfDay < 12 ) {
			$want1=sprintf("%d:00AM", $hourOfDay);
			$want2=sprintf("%d:30AM", $hourOfDay);
		    }
		    elsif ( $hourOfDay == 12 ) {
			$want1=sprintf("%d:00PM", $hourOfDay);
			$want2=sprintf("%d:30PM", $hourOfDay);
		    }
		    else {
			$want1=sprintf("%d:00PM", $hourOfDay-12);
			$want2=sprintf("%d:30PM", $hourOfDay-12);
		    }

		    #print STDERR "column $col in time row says $timerow[$col]->{prog_title}, expect $want1\n";
		    #print STDERR "  and says $timerow[$col+1]->{prog_title}, expect $want2\n";
		
		    my $field1=$timerow[$col];
		    my $field2=$timerow[$col+1];

		    if ( $field1->{prog_title} eq "$want1" ) {
			delete($field1->{prog_title});

			$field1->{timeinfo}=[$hourOfDay*60, $curday, $year];
		    }
		    else {
			die "even column $col in time row says $field1->{prog_title}, not $want1";
		    }
		    
		    if ( $field2->{prog_title} eq "$want2" ) {
			delete($field2->{prog_title});
			$field2->{timeinfo}=[$hourOfDay*60+30, $curday, $year];
		    }
		    else {
			die "odd column $col+1 in time row says $field2->{prog_title}, not $want2";
		    }
		}
	    }
	
	    #print STDERR "RESULT:\n".dumpMe(\@noSubHeadersTable)."\n/RESULT:\n";

	    if ( $SegmentsInTimeLine == -1 ) {
		$SegmentsInTimeLine=scalar(@timerow);
	    }
	    
	    # slap this table onto the start of the existing one
	    # - append each row onto the end of the existing table (or init a new one)
	    #

	    for (my $row=1 ; $row< scalar(@noSubHeadersTable) ; $row++) {
		my @r=@{$noSubHeadersTable[$row]};
		my $totalcolspan=0;
		    
		for (my $j=1 ; $j<scalar(@r) ; $j++ ) {
		    $totalcolspan+=$r[$j]{colspan};
		}
		if ( $totalcolspan != $SegmentsInTimeLine ) {
		    warn "ERROR: row $row has $totalcolspan column spans, not $SegmentsInTimeLine\n";
		    if ( defined($r[0]->{prog_desc}) ) {
			warn "       looks like it might be channel ".$r[0]->{prog_desc}."\n";
		    }
		    warn "       adjusting length of first program, attempting to continue\n";
		    if ( $debug ) {
			for (my $j=1; $j<scalar(@r) ; $j++ ) {
			    print STDERR "schedule for $row $j :".dumpMe(\%{$r[$j]})."\n";
			}
		    }
		    $r[1]{colspan}+=($SegmentsInTimeLine-$totalcolspan);
		    $row--;
		}
	    }

	    # track schedule only if table was deemed sane
	    # yes, I know currently this can't happen :)
	    if ( $scheduleCorrupt == 0 ) {
		push(@TimeTable, @timerow);
		$DayOfSchedules->{$Schedules}=\@noSubHeadersTable;
		$Schedules++;
	    }
	    else {
		printf STDERR "table parse failed, dropping $hours_per_listing hours of programs from %4d-%02d-%02d... attempting to continue\n", $year, $month, $day;
	    }
	}
	my @DayTable;

	for (my $sch=0; $sch < $Schedules ; $sch++ ) {
	    my @noSubHeadersTable=@{$DayOfSchedules->{$sch}};

	    #push(@{$DayTable[0]}, @{$noSubHeadersTable[0]});
	    
	    for (my $row=0 ; $row< scalar(@noSubHeadersTable) ; $row++) {
		my @r=@{$noSubHeadersTable[$row]};
		if ( $sch != 0 ) {
		    splice(@r,0,1);
		}
		push(@{$DayTable[$row]}, @r);
	    }
	}

	#print STDERR "TimeTable is :".dumpMe(\@TimeTable)."\n";
	$SegmentsInTimeLine=scalar(@TimeTable);

	# verify that:
	# - colspan total spans all columns
	# - merge cells that say 'cont to next',
	#   and next says 'cont from previous'
	for (my $row=0 ; $row< scalar(@DayTable) ; $row++) {
	    my @r=@{$DayTable[$row]};
	    my $totalcolspan=0;
	    
	    for (my $i=1 ; $i<scalar(@r) ; $i++ ) {
		$totalcolspan+=$r[$i]{colspan};
	    }
	    if ( $totalcolspan != $SegmentsInTimeLine ) {
		warn "ERROR: row $row has $totalcolspan column spans, not $SegmentsInTimeLine\n";
		if ( defined($r[0]->{prog_desc}) ) {
		    warn "       looks like it might be channel ".$r[0]->{prog_desc}."\n";
		}
		for (my $i=1; $i<scalar(@r) ; $i++ ) {
		    print STDERR "schedule for $row $i :".dumpMe(\%{$r[$i]})."\n";
		}
	    }
	}

	# finished adding a day's worth of schedules

	# slap this table onto the start of the existing one
	# - append each row onto the end of the existing table (or init a new one)
	#
	for (my $i=0 ; $i< scalar(@DayTable) ; $i++) {
	    if ( @WholeTable ) {
		my @row=@{$DayTable[$i]};
		#print STDERR "Ignoring Channel row: ".dumpMe(\%{$row[0]})."\n";
		splice(@{$DayTable[$i]}, 0, 1);
	    }
	    push(@{$WholeTable[$i]}, @{$DayTable[$i]});
	}
	push(@TimeLine, @TimeTable);
    }
	
    # verify timeline contains 30 minute intervals all the way across
    if ( 1 ) {
	my $lasttime;
	my $timecol=0;
	foreach my $cell (@TimeLine) {
	    $timecol++;
	    my ( $minOfDay, $dayofyear, $year)=@{$cell->{timeinfo}};
	    my $minOfYear=$minOfDay+($dayofyear * 24*60);
	    if ( defined($lasttime) ) {
		if ( $minOfYear - $lasttime != 30 ) {
		    die "time cell $timecol is not 30 min later than last ($cell->{local_time},$lasttime)";
		}
		#if ( $cell->{local_time}-$lasttime == 30*60*1000 ) {
		 #   die "time cell $timecol is not 30 min later than last ($cell->{local_time},$lasttime)";
		#}
	    }
	    $lasttime=$minOfYear;
	    delete($cell->{colspan});
	    delete($cell->{fieldtag});
	}
    }

    # remove channel column (column 1) saved away
    my @Channels;
    for (my $nrow=0 ; $nrow< scalar(@WholeTable) ; $nrow++) {
	my @row=@{$WholeTable[$nrow]};

	if ( $debug > 1 ) { print STDERR "checking out row:$nrow:".dumpMe(\@row)."\n"; }

	my $ch=$row[0];
	my $channel;
	
	if ( $dataFormat eq "tvguidelive" ) {
	    # in tvguidelive, () appear outside of url like '(<a href='http://www.ctv.ca' target=_blank>CTV</a>)'
	    if ( defined($ch->{prog_desc}) && $ch->{prog_desc} eq ")" && 
		 defined($ch->{prog_subtitle}) ) {
		$ch->{prog_subtitle}.=")";
		delete($ch->{prog_desc});
	    }
	}
	# remove () around things
	foreach my $key (keys %{$ch}) {
	    $ch->{$key}=~s/^\(//g;
	    $ch->{$key}=~s/\)$//g;
	}
	
	die "channel info spanned more than one column" if ( $ch->{colspan} != 1);
	    
	$channel->{url}=$ch->{prog_href} if ( defined($ch->{prog_href}) );
	
	my @poss;
	push(@poss, $ch->{prog_title})    if ( defined($ch->{prog_title}));
	push(@poss, $ch->{prog_subtitle}) if ( defined($ch->{prog_subtitle}));
	push(@poss, $ch->{prog_desc})     if ( defined($ch->{prog_desc}));
		
	# if the channel number appears separately from the station id/affiliate
	# then the affiliate appears next, otherwise the station id appears with
	# the channel number
	foreach my $possible (@poss) {
	    if ( !defined($channel->{number}) ) {
		if ( $possible=~m/^([0-9]+)\s*$/o ) {
		    $channel->{number}=$1;
		    next;
		}
		elsif ( $possible=~m/^([0-9]+)\s+/o ) {
		    $channel->{number}=$1;
		    $possible=~s/^([0-9]+)\s*//o;
		    
		    if ( defined($channel->{localStation}) ) {
			die "expected $possible to be the local station here";
		    }
		    $channel->{localStation}=$possible;
		    next;
		}
	    }
	    if ( $dataFormat eq "clicktv" ) {
		if ( !defined($channel->{affiliate}) ) {
		    $channel->{affiliate}=$possible;
		}
		elsif ( !defined($channel->{localStation}) ) {
		    $channel->{localStation}=$possible;
		}
		else {
		    warn "problems with row:$nrow:".dumpMe(\%{$row[0]})."\n";
		    die "don't know where to place $possible";
		}
	    }
	    else {
		if ( !defined($channel->{localStation}) ) {
		    $channel->{localStation}=$possible;
		}
		elsif ( !defined($channel->{affiliate}) ) {
		    $channel->{affiliate}=$possible;
		}
		else {
		    warn "problems with row:$nrow:".dumpMe(\%{$row[0]})."\n";
		    die "don't know where to place $possible";
		}
	    }
	}

	# verify and warn that the if IND appeared, it wasn't assigned to the localstation.
	if ( defined($channel->{localStation}) && $channel->{localStation}=~/^IND$/io ) {
	    warn "warning: channel $channel->{number} has call lets IND, parse may have failed";
	}
	if ( $debug ) { print STDERR "loaded channel:".dumpMe(\%{$channel})."\n";}
	
	push(@Channels, $channel);
	if ( $debug > 1 ) { print STDERR "loaded channel:".dumpMe($self)."\n";}

	# remove channel row
	splice(@{$WholeTable[$nrow]}, 0,1);
    }

    if ( !defined($self->{Channels}) ) {
	push(@{$self->{Channels}}, @Channels);
    }
    else {
	if ( scalar(@{$self->{Channels}}) != scalar(@Channels) ) {
	    print(STDERR "error: # of channels changed across schedules ". 
		  scalar(@{$self->{Channels}})." != ".scalar(@Channels)."\n");
	    return(0);
	}
	my @savedCh=@{$self->{Channels}};
	for (my $ch=0; $ch<scalar(@savedCh) ; $ch++ ) {
	    for my $opkey ('number', 'url', 'localStation', 'affiliate' ) {
		if ( defined($Channels[$ch]->{$opkey}) == defined($savedCh[$ch]->{$opkey}) ) {
		    if ( defined($Channels[$ch]->{$opkey}) && $Channels[$ch]->{$opkey} ne $savedCh[$ch]->{$opkey} ) {
			print(STDERR "error: channel $ch changed $opkey:".
			      $Channels[$ch]->{$opkey}." != ".$savedCh[$ch]->{$opkey}."\n");
			return(0);
		    }
		}
		else {
		    if ( defined($Channels[$ch]->{$opkey}) ) {
			print(STDERR "error: new channel $ch missing $opkey\n");
			return(0);
		    }
		    else {
			print(STDERR "error: new channel $ch has $opkey defined, different from last time\n");
			return(0);
		    }
		}
	    }
	}
    }

    # merge cells that say cont to next, and next says cont from previous
    for (my $nrow=0 ; $nrow< scalar(@WholeTable) ; $nrow++) {
	print STDERR "checking row $nrow\n" if ( $debug > 1 );
	my @row=@{$WholeTable[$nrow]};

	for (my $col=0 ; $col<scalar(@row)-1 ; $col++ ) {
	    my $cell1=$row[$col];
	    my $cell2=$row[$col+1];

	    if ( defined($cell1->{contToNextListing}) ) {
		if ( !defined($cell2->{contFromPreviousListing}) ) {
		    warn "cell [col,row] [$col+1,$nrow] missing link to previous listing\n";
		}
		if ( defined($cell1->{prog_title}) && defined($cell2->{prog_title}) &&
		     $cell1->{prog_title} eq $cell2->{prog_title} ) {
		    if ( defined($cell2->{contToNextListing}) ) {
			$cell1->{contToNextListing}=$cell2->{contToNextListing};
		    }
		    else {
			delete($cell1->{contToNextListing});
		    }
		    $cell1->{colspan}+=$cell2->{colspan};
		    splice(@{$WholeTable[$nrow]}, $col+1, 1);
		    @row=@{$WholeTable[$nrow]};
		    $col--;
		    next;
		}
	    }
	}
    }

    # traverse WholeTable and:
    # - calculate prog ref # as needed
    # - move programs off into separate Programs hash
    # - remove some hash entries we no longer need
    # - identify programs where actors list contain entries
    #   from the unidentifiedQualifiers list (because it
    #   wasn't until later we noticed these as qualifiers and
    #   not actors
    for (my $nrow=0 ; $nrow< scalar(@WholeTable) ; $nrow++) {
	my @row=@{$WholeTable[$nrow]};

	if ( $debug > 1 ) { print STDERR "checking out row:$nrow:".dumpMe(\@row)."\n"; }

	for (my $col=0 ; $col<scalar(@row) ; $col++ ) {
	    my $cell=$row[$col];

	    $cell->{prog_duration}=$cell->{colspan}*30;
	    if ( defined($cell->{prog_href}) ) {
		if ( $cell->{prog_href}=~m/PDetail\(([0-9]+),([0-9]+)/o ) {
		    $cell->{pref}="$1-$2";
		}
		else {
		    die "unable to get pref from $cell->{prog_href}";
		}
		delete($cell->{prog_href});
	    }
	    else {
		# for programs which don't have ref #s, we assign program ref #
		# based on program title and duration, we ignore all other differences.
		
		my $key="$cell->{prog_title}:$cell->{prog_duration}";
		
		if ( defined($self->{ProgByRefNegative}->{$key}) ) {
		    $cell->{pref}=$self->{ProgByRefNegative}->{$key};
		}
		else {
		    $self->{lastNegative_ProgByRef}--;
		    $self->{ProgByRefNegative}->{$key}=$self->{lastNegative_ProgByRef};
		    $cell->{pref}=$self->{lastNegative_ProgByRef};
		}
	    }
	    
	    my $prog;

	    foreach my $key ('duration',
			     'title',
			     'subtitle',
			     'desc',
			     'ratings_VCHIP', 
			     'ratings_VCHIP_Expanded', 
			     'ratings_MPAA',
			     'ratings_warnings', 
			     'qualifiers',
			     'director',
			     'year',
			     'stars_rating') {
		if ( defined($cell->{"prog_$key"}) ) {
		    $prog->{$key}=$cell->{"prog_$key"};
		    delete($cell->{"prog_$key"});
		}
	    }
	    # since identifying actors lists in the schedule is
	    # so hokey, we re-run through the actors we found
	    # and remove names that were later identified as
	    # being program qualifiers on the unidentifiedQualifiers
	    # list.
	    # 
	    if ( defined($cell->{prog_actors}) ) {
		for my $actor (@{$cell->{prog_actors}}) {
		    if ( defined($self->{undefQualifiers}->{$actor}) ) {
			warn "fixing incorrectly identified actor '$actor'\n" if ( $debug );
		    }
		    else {
			push(@{$prog->{actors}}, $actor);
		    }
		}
		delete($cell->{"prog_actors"});
	    }

	    $prog->{refNumber}=$cell->{pref};
	    if ( defined($self->{Programs}->{$cell->{pref}}) ) {
		if ( $verify ) {
		    verifyProgramMatches($prog, $self->{Programs}->{$cell->{pref}});
		}
	    }
	    else {
		$self->{Programs}->{$cell->{pref}}=$prog;
	    }
	    
	    # remove some no-unneeded entires
	    delete($cell->{fieldtag});
	    # rename colspan to 'numberOf30MinSegments'
	    $cell->{numberOf30MinSegments}=$cell->{colspan};
	    delete($cell->{colspan});
	}
    }

    $self->{Schedule}=\@WholeTable;
    $self->{TimeLine}=\@TimeLine;
    
    print STDERR "Read Schedule with:";
    print STDERR "".scalar(@{$self->{Channels}})." channels, ";
    print STDERR "".scalar((keys %{$self->{Programs}}))." programs, ";
    print STDERR "".(scalar(@{$self->{TimeLine}})/2)." hours\n";
	    
    return(1);
}

sub getAndParseDetails($$)
{
    my ($self, $prog_ref)=@_;
    my $nprog;

    my $url=$self->getDetailURL($prog_ref);
    print STDERR "retrieving: $url..\n";
		
    my $urldata=$self->getDetailURLData($url);
    if ( !defined($urldata) ) {
	warn "unable to read url $url\n";
	return(undef);
    }

    if ( $debug ) {
	print STDERR "\tread ".length($urldata). " bytes of html\n";
	print STDERR "urldata:\n'$urldata'\n" if ( $debug>1 );
    }

    # grab url at imdb if one exists
    # looks like: <A href="http://us.imdb.com/M/title-exact?Extreme%20Prejudice%20%281987%29" target="IMDB">
    if ( $urldata=~s;<A href=\"(http://[^.]+\.imdb\.com/M/title-exact\?[^\"])+\" target=\"IMDB\">;;og ) { 
	#$url=$1;
    }
    
    if ( $urldata=~s;<font style=\"EpisodeTitleFont\"> - ([^<]+)</font></td></TR>;;ogi ) { # "
	$nprog->{subtitle}=$1;
    }
    
    study($urldata);

    # remove some html tags for easier parsing
    $urldata=~s/<\/*nobr>//ogi;
    $urldata=~s/[\r|\n]//og;
    $urldata=~s/<font [^>]+>//ogi;
    $urldata=~s/<\/font>//ogi;
    $urldata=~s/<\/*a[^>]*>//og;
    $urldata=~s/<![^>]+>//og;
		  
    #print STDERR "detail url contains='$urldata'\n";
    while ( $urldata=~s/<TD[^>]*>([a-zA-Z]+):<\/TD><T[DR]>([^<]+)<\/T[DR]>//oi ) {
	my $field=$1;
	my $desc=$2;
	
	# convert html tags and the like, removing write space etc.
	$desc=ClickListings::ParseTable::massageText($desc);
	
	#print STDERR "detail: $field: $desc\n";
	if ( $field eq "Type" ) {
	    if ( $desc=~s/\s*\(([0-9]+)\)//o ) {
		my $str=$1;
		$nprog->{year}=$str;
	    }
	    my @arr=split(/\s*\/\s*/, $desc);
	    #print STDERR "warning: ignoring Type defined as ". join(",", @arr)."\n";
	    foreach my $a (@arr) {
		$nprog->{category}->{$a}++;
	    }
	    #push(@{$nprog->{category}}, @arr);
	}
	elsif ( $field eq "Duration" ) {
	    # ignore - don't need this
	    # check for duration (ie '(6 hr) or (2 hr 30 min)')
	    my $min;
	    if ($desc =~m/([0-9]+)\s*hr/oi ) {
		$min=$1*60;
	    }
	    elsif ($desc =~m/([0-9]+)\s*hr\s*([0-9]+)\s*min/oi ) {
		$min=$1*60+$2;
	    }
	    elsif ($desc =~m/([0-9]+)\s*min/oi ) {
		$min=$1;
	    }
	    else {
		warn "warning: failed to parse Duration field $desc\n";
	    }
	    # don't replace duration, believe what is in the schedule grid instead.
	    $nprog->{duration}=$min if ( defined($min) );
	}
	elsif ( $field eq "Description" ) {
	    my @details;
	    
	    #print STDERR "parsing $desc..\n";
	    while ( $desc=~m/\s*\(([^\)]+)\)[\s\.]*$/o ) {
		my $detail=$1;
		#print STDERR "parsing got $detail\n";
		
		# strip off what we found and any white space
		$desc=~s/\s*\([^\)]+\)[\s\.]*$//o;
		push(@details, $detail);
	    }
	    if ( @details ) {
		$nprog->{details}=\@details;
	    }
	    if ( length($desc) ) {
		$nprog->{desc}=$desc;
	    }
	}
	elsif ( $field eq "Director" ) {
	    $desc=~s/,\s+/,/og;
	    $nprog->{director}=$desc;
	}
	elsif ( $field eq "Performers" ) {
	    my @actors=split(/\s*,\s*/, $desc);
	    $nprog->{actors}=\@actors;
	}
	# Parental Ratings are:
	#     TV-Y, TV-Y7, TV-G, TV-PG, TV-14, TV_MA.
	# 
	elsif ( $field eq "Parental Rating" ) {
	    push(@{$nprog->{ratings}}, "Parental Rating:$desc");
	}
	# Expanded ratings are:
	#     Adult Language
	#     Adult Situations
	#     Brief Nudity
	#     Graphic Violence
	#     Mild Violence
	#     Nudity
	#     Strong Sexual Content
	#     Violence
	elsif ( $field eq "Expanded Rating" ) {
	    push(@{$nprog->{ratings}}, "Expanded Rating:$desc");
	}
	# 
	# MPAA ratings include:
	#  G, PG, PG-13, R, Mature,NC-17, NR(not rated), GP, X.
	#
	elsif ( $field eq "Rated" ) {
	    push(@{$nprog->{ratings}}, "MPAA Rating:$desc");
	}
	else {
	    warn "$prog_ref: unidentified field '$field' has desc='$desc'\n";
	}
    }

    if ( defined($nprog->{category}) ) {
	my $value=join(',', keys (%{$nprog->{category}}) );
	delete($nprog->{category});
	push(@{$nprog->{category}}, split(',', $value));
    }
    else {
	#print STDERR "\t program detail produced no Type info.. defaulting to Other\n" if ($debug);
	push(@{$nprog->{category}}, "Other");
    }
    return($nprog);
}

sub mergeDetails($$)
{
    my($self, $prog, $nprog)=@_;

    # if we've decided to, only trust certain details when they appear
    # in the listing and ignore them in the 'details' reference page.
    # - sometimes these entries in the details page are in-accurate
    #   or out of date.
    if ( !$self->{TrustAllDetailsEntries} ) {
	for my $key ( 'details', 'subtitle', 'desc', 'director',
		     'actors', 'ratings' ) {
	    delete($nprog->{$key}) if ( defined($nprog->{$key}) );
	}
    }

    if ( defined($nprog->{subtitle}) ) {
	if ( defined($prog->{subtitle}) && $nprog->{subtitle} ne $prog->{subtitle} ) {
	    warn "warning: subtitle of $prog->{title} is different\n";
	    warn "warning: '$nprog->{subtitle}' != '$prog->{subtitle}'\n";
	}
	$prog->{subtitle}=$nprog->{subtitle};
	delete($nprog->{subtitle});
    }
    
    if ( defined($nprog->{year}) ) {
	if ( defined($prog->{year}) && $nprog->{year} ne $prog->{year} ) {
	    warn "warning: year of $prog->{title} is different\n";
	    warn "warning: '$nprog->{year}' != '$prog->{year}'\n";
	}
	#print STDERR "$prog->{prog_ref}: year is $str\n";
	$prog->{year}=$nprog->{year};
	delete($nprog->{year});
    }
    
    if ( defined($nprog->{category}) ) {
	push(@{$prog->{category}}, @{$nprog->{category}});
	delete($nprog->{category});
    }
    
    if ( defined($nprog->{duration}) ) {
	if ( defined($prog->{duration}) ) {
	    if ( $nprog->{duration} ne $prog->{duration} ) {
		if ( $debug ) {
		    warn "warning: duration of $prog->{title} is different\n";
		    warn "warning: '$nprog->{duration}' != '$prog->{duration}'\n";
		    if ( defined($prog->{contFromPreviousListing}) ) {
			warn "warning: was expected (cont from previous listing)\n";
		    }
		}
	    }
	}
	# don't replace duration, believe what is in the schedule grid instead.
	#$prog->{duration}=$min if ( defined($min) );
	delete($nprog->{duration});
    }
    
    if ( defined($nprog->{details}) ) {
      ClickListings::ParseTable::evaluateDetails($prog, @{$nprog->{details}});
	delete($nprog->{details});
    }

    if ( defined($nprog->{desc}) ) {
	if ( defined($prog->{desc}) && $nprog->{desc} ne $prog->{desc} ) {
	    warn "warning: description of $prog->{title} is different\n";
	    warn "warning: '$nprog->{desc}' != '$prog->{desc}'\n";
	}
	#print STDERR "$prog->{prog_ref}: description is $nprog->{desc}\n";
	if ( length($nprog->{desc}) ) {
	    $prog->{desc}=$nprog->{desc};
	}
	delete($nprog->{desc});
    }

    if ( defined($nprog->{director}) ) {
	if ( defined($prog->{director}) && $nprog->{director} ne $prog->{director} ) {
	    warn "warning: director of $prog->{title} is different\n";
	    warn "warning: '$nprog->{director}' != '$prog->{director}'\n";
	}
	#print STDERR "$prog->{prog_ref}: director is $nprog->{director}\n";
	$prog->{director}=$nprog->{director};
	delete($nprog->{director});
    }
    if ( defined($nprog->{actors}) ) {
	my @actors=@{$nprog->{actors}};
	if ( defined($prog->{actors}) ) {
	    my @lactors=@{$prog->{actors}};
	    my $out=0;
	    if ( scalar(@lactors) != scalar(@actors) ) {
		warn "warning: actor list different size\n";
		$out++;
	    }
	    my $top=scalar(@lactors);
	    if ( scalar(@actors) > $top ) {
		$top=scalar(@actors);
	    }
	    for (my $num=0; $num<$top ; $num++ ) {
		if ( $lactors[$num] ne $actors[$num] ) {
		    warn "warning: actor $num '".$lactors[$num]." != ".$actors[$num]."\n";
		    $out++;
		}
	    }
	    warn "warning: actor list different for $prog->{title} in $out ways\n" if ( $out );
	}
	$prog->{actors}=\@actors;
	#print STDERR "$prog->{prog_ref}: actors defined as ". join(",", @actors)."\n";
	delete($nprog->{actors});
    }

    if ( defined($nprog->{ratings}) ) {
	if ( !defined($prog->{ratings}) ) {
	    push(@{$prog->{ratings}}, @{$nprog->{ratings}});
	}
	delete($nprog->{ratings});
    }
    if ( scalar(keys %{$nprog}) != 0 ) {
	warn "$prog->{pref}: ignored scaped values of nprog:".dumpMe($nprog)."\n";
    }
    return($prog);
}

sub expandDetails
{
    my ($self, $cachePath)=@_;

    my %ptypeHash;
    my $foundInCache=0;

    my $ptypedb;

    if ( defined($cachePath) && length($cachePath) ) {
	$ptypedb=tie (%ptypeHash, "DB_File", $cachePath, O_RDWR|O_CREAT) || die "$cachePath: $!";
    }

    my $count=scalar((keys %{$self->{Programs}}));

    my $done=0;
    foreach my $refNumber (keys %{$self->{Programs}}) {
	$done++;
	my $percentDone=($done*100)/$count;
	if ( $percentDone > 1 && $percentDone%10 == 0 ) {
	    printf STDERR "resolved %.0f%% of the programs.. %d to go\n", $percentDone, $count-$done;
	}
	if ( $done % 10 == 0 ) {
	    # flush db every now and again
	    $ptypedb->sync() if ( defined($ptypedb) );
	}

	my $prog=$self->{Programs}->{$refNumber};
	if ( $refNumber >= 0 ) {
	    
 	    my $key=$prog->{title};
	    #$key.=":";
	    #$key.="$prog->{subtitle}" if ( defined($prog->{subtitle}) );
	    #$key.=":";
	    #$key.="$prog->{desc}" if ( defined($prog->{desc}) );
	    
	    my $value=$ptypeHash{$key};
	    if ( defined($value) ) {
		my %info;
		eval($value);
		my $nprog=\%info;
		
		$self->{Programs}->{$refNumber}=$self->mergeDetails($prog, $nprog);
		$foundInCache++;
	    }
	    else {
		warn "$prog->{title}: missing program type, looking it up...\n" if ($debug);
		my $info=$self->getAndParseDetails($refNumber);
		if ( !defined($info) ) {
		    warn "\t failed to parse url\n" if ($debug);
		}
		else {
		    # only add things to the db if the cache is enabled
		    if ( defined($ptypedb) ) {
			my $d=new Data::Dumper([\%{$info}], ['*info']);
			$d->Purity(0);
			$d->Indent(0);
			$ptypeHash{$key}=$d->Dump();
		    }
		    
		    $self->{Programs}->{$refNumber}=$self->mergeDetails($prog, $info);
		}
	    }
	}
	else {
	    warn "$prog->{title}: missing program type and ref#, defaulting to <undef>\n" if ($debug);
	}
    }
    if ( defined($ptypedb) ) {
	untie(%ptypeHash);
    }
    return($foundInCache);
}

sub getChannelList
{
    my ($self)=@_;

    if ( defined $self->{Channels} ) {
	return (@{$self->{Channels}});
    }
    else {
	warn "channels list undefined";
	return ();
    }
}

# create a conversion string
sub createDateString($$$$$)
{
    my ($minuteOfDay, $dayOfYear, $year, $additionalMin, $time_zone)=@_;
    
    if ( $additionalMin != 0 ) {
	$minuteOfDay+=$additionalMin;

	# deal with case where additional minutes pushes us over end of day
	if ( $minuteOfDay > 24*60 ) {
	    $minuteOfDay-=24*60;
	    $dayOfYear++;

	    # check and deal with case where this pushes us past end of year
	    my $isleap=&Date_LeapYear($year);
	    if ($dayOfYear >= ($isleap ? 367 : 366)) {
		$year++;
		$dayOfYear-=($isleap ? 367 : 366);
	    }
	}
    }

    # calculate year,month and day from nth day of year info
    my ($pYEAR,$pMONTH,$pDAY,$pHR,$pMIN,$pSEC)=Date::Manip::Date_NthDayOfYear($year, $dayOfYear);

    # set HR and MIN to what they should really be
    $pHR=int($minuteOfDay/60);
    $pMIN=$minuteOfDay-($pHR*60);

    return(sprintf("%4d%02d%02d%02d%02d00 %s", $pYEAR, $pMONTH, $pDAY, $pHR, $pMIN, $time_zone));
}

sub getProgramStartTime
{
    my ($self)=@_;
    my @timerow=@{$self->{TimeLine}};
    my ($progMinOfDay, $progDayOfYear, $progYear) = @{$timerow[0]->{timeinfo}};
    return(createDateString($progMinOfDay, $progDayOfYear, $progYear, 0, $self->{TimeZone}));
}

sub getProgramsOnChannel
{
    my ($self, $channelindex)=@_;
    my @channels=$self->getChannelList();
    my @schedule=@{$self->{Schedule}};
    my @timerow=@{$self->{TimeLine}};

    my @programs;
    
    my $timecol=0;
    my @row=@{$schedule[$channelindex]};

    for (my $col=0 ; $col<scalar(@row) ; $col++ ) {
	my $cell=$row[$col];
	
	my ($progMinOfDay, $progDayOfYear, $progYear) = @{$timerow[$timecol]->{timeinfo}};

	# as an optimization create start date string and cache it, since it won't change
	if ( !defined($timerow[$timecol]->{timeinfo_DateString}) ) {
	    $timerow[$timecol]->{timeinfo_DateString}=createDateString($progMinOfDay, $progDayOfYear, $progYear, 0, $self->{TimeZone});
	}
	my $ret;
	
	$ret->{start_time}=$timerow[$timecol];
	$ret->{start}=$timerow[$timecol]->{timeinfo_DateString};
	$ret->{end}=createDateString($progMinOfDay, $progDayOfYear, $progYear, ($cell->{numberOf30MinSegments}*30), $self->{TimeZone});
	$ret->{channel}=$channels[$channelindex];
	$ret->{program}=$self->{Programs}->{$cell->{pref}};
	$ret->{durationMin}=int($cell->{numberOf30MinSegments}*30);

	if ( defined($cell->{contFromPreviousListing}) ) {
	    $ret->{contFromPreviousListing}=$cell->{contFromPreviousListing};
	}
	if ( defined($cell->{contToNextListing}) ) {
	    $ret->{contToNextListing}=$cell->{contToNextListing};
	}

	push(@programs, $ret);

	# adjust timecol depending on how long the program is.
	$timecol+=($cell->{numberOf30MinSegments});
    }
    return(@programs);
}

1;
