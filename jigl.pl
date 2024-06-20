#!/usr/bin/perl -w
# jigl - Jason's Image Gallery
#
####################
#  GNU General Public License
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
####################
# Author: Jason Paul

use strict;
use warnings;

use Getopt::Long;       # options parsing
use Text::ParseWords;   # for converting the config options into an array
use File::Copy;         # for the copy and move functions
use File::Path;         # for the rmtree function
use Cwd;                # directory functions
use DirHandle;          # for recursive dir handling
use POSIX qw(strftime); # for proper localtime handling
use File::Glob qw(:nocase); # force case insensitivity

######################
### setup some variables
######################

my $version     = "v2.0.2-Beta";
my $author      = "Jason Paul";
my $progName    = $0;
my $jpgTypeStr  = "*.jpg *.jpeg";
my $gifTypeStr  = "*.gif";
my $pngTypeStr  = "*.png";
my $fileTypeStr = "$jpgTypeStr $gifTypeStr $pngTypeStr";
my $jiglRCDir   = "$ENV{HOME}/.jigl";        # dir for global themes/configs
my $jiglRCFile  = $jiglRCDir . "/jigl.opts"; # name of users global config file
my $gblThemeDir = $jiglRCDir . "/themes";    # global name of dir for themes
my $galDatFile  = "gallery.dat";       # name of gallery data file
my $themeDir    = "theme";             # dir for optional theme files
my $thumbDir    = "thumbs";            # thumbnail directory
my $thumbPrefix = "$thumbDir/thumb_";  # thumbnail prefix
my $slideDir    = "slides";            # slide directory
my $slidePrefix = "$slideDir/slide_";  # slide prefix
my $exifProg    = "jhead";             # program to extract exif info
my $imgInfoProg = "identify";          # program to display image info
my $scaleProg   = "convert";           # program to resize images
my $waterMarkProg = &getWatermarkProg; # program to watermark images
my $indexPrefix = "index";             # name of index file 
my $indexExt    = ".html";             # extension for the index file
my $indexTmpl   = "index_template";    # name of index template file
my $slideTmpl   = "slide_template";    # name of slide template file
my $jsfile      = "jigl.js";           # name of JavaScript file
my $infoTmpl    = "info_template";     # name of info template file
my $gblIndexTmpl = $gblThemeDir . "/default/" . $indexTmpl; # global index template
my $gblJsFile    = $gblThemeDir . "/default/" . $jsfile;    # global javascript
my $gblSlideTmpl = $gblThemeDir . "/default/" . $slideTmpl; # global slide template
my $gblInfoTmpl  = $gblThemeDir . "/default/" . $infoTmpl;  # global info template
my @imgMgkVer    = &checkSiteInstall;  # check for img tools; return ImageMagick ver

######################
### end variable setup
######################

# Get the list of directories we're going to be running the
# program on.
my @dirs = &getDirs;

# Initial system-wide options to the defaults
# This needs to be done first.
my %optsSys = &setSystemOpts;

# check to see if the user has a resource file in their home dir.
# If they do get these options here.
my %optsRC = &getRCOpts;
# check the validity of the options (i.e. bounds check)
%optsRC = &checkOpts(\%optsRC, \%optsSys);

# get the command line options.
print "Checking the command line options.\n";
my %optsCmd = &getCmdOpts({});
# check the validity of the options (i.e. bounds check)
%optsCmd = &checkOpts(\%optsCmd, \%optsSys);

# save the starting dir so we know how to get back
my $startDir = cwd;

# check if the recursive option was used on the command line
# this option will only be recognized on the command line
if ($optsCmd{r}) {
    my @rDirs = ();
    # recurse through each dir that was passed to us on the cmd line
    foreach my $dir (@dirs) {
        push @rDirs,$dir;
        push @rDirs,&recursiveDirList($dir,());
    }
    @dirs = @rDirs;
}

# run on each directory given on the cmdLine.
foreach my $dir (@dirs) {

    # skip any directory that is not valid
    if (! (-d $dir)) {
        for (my $i=0;$i<30;$i++) {print "-"};
        print "\n\'$dir\' is not a valid directory. Skipping!\n";
        next;
    }

    die "Can't cd to $dir: $!\n" unless chdir $dir;
    for (my $i=0;$i<30;$i++) {print "-"};
    print "\nProcessing directory \'$dir\'\n\n";

    # get any options from this dirs gallery.dat file
    my %optsGal = &getGalOpts;
    # check the validity of the options (i.e. bounds check)
    %optsGal = &checkOpts(\%optsGal, \%optsSys);

    # the final options hash.
    my %opts = mergeOpts(\%optsSys,\%optsRC,\%optsGal,\%optsCmd);
    print "Checking the final options for validity\n";
    %opts = &checkOpts(\%opts, \%optsSys);

    # skip this directory if it's the output dir. We have to wait untill here
    # to check this because we have to wait for all the options to be processed
    # and merged first.
    if ($dir =~ /\/$opts{wd}/) {
        print "Skipping this directory because it's the output directory\n";
        die "Can't cd to $startDir $!\n" unless chdir $startDir;
        next;
    }

    # was the -h or --help option called?
    &printUsage if $opts{h};

    # was the -v or --version option called?
    &printVersion if $opts{v};

    # generate the albumInfo array
    my $albumInfo = &genAlbumInfo(\%opts,$dir);

    # reset the titlebar/title for the gallery if the -it option is used
    $albumInfo->{titlebar} = $opts{it} if ($opts{it} ne "");
    $albumInfo->{title} = $opts{it} if ($opts{it} ne "");

    if (($#{$albumInfo->{images}} == -1) && (!($opts{cg}))) {
        print "No image files were found in \'$dir\'\nSkipping directory.\n";
    } elsif (!($opts{cg})) {

        # generate thumbnails
        &genThumbs(\%opts,$albumInfo);

        # generate slides
        &genSlides(\%opts,$albumInfo) if $opts{gs} or $opts{gi};

        # remove any existing template files from local gallery and
        # remove the global default theme so it can be regenerated
        &removeFiles(($indexTmpl,$slideTmpl,$infoTmpl,"$gblThemeDir/$optsSys{theme}")) if $opts{ut};

        # remove any existing html files to prevent stale files
        my @fileList = glob($indexPrefix . "*" . $indexExt);
        push @fileList,glob("[0-9]*" . $indexExt);
        &removeFiles(@fileList);

        # read in theme and store as a hash
        my %theme = &readTheme(\%opts);

        print "Using theme '$opts{theme}' for html pages\n";

        # generate JavaScript file (only if generating slides)
        &genJsFile(\%opts,\%theme,$albumInfo)		if $opts{gs};

        # generate slide pages
        &genSlidePages(\%opts,\%theme,$albumInfo)	if $opts{gs};

        # generate info page
        &genInfoPages(\%opts,\%theme,$albumInfo)	if $opts{gi};

        # generate the index page(s)
        for my $page (0 .. $albumInfo->{numPages}) {
            # figure out which thumbnails we're going to list on this page
            my $startIndex = $page * ($opts{iw} * $opts{ir});
            my $endIndex   = (($opts{iw} * $opts{ir}) * ($page + 1)) - 1;
            if (($endIndex >= $#{$albumInfo->{images}}) or $endIndex == -1) {
                $endIndex   = $#{$albumInfo->{images}};
            }
            &genIndexPage(\%opts,\%theme,$albumInfo,$page,$startIndex,$endIndex);
        }

        # Copy any necessary theme files to the local themeDir
        # first remove the current themeDir so it doesn't get stale files
        rmtree("$themeDir",0,0) if -d $themeDir;
        
        # flag to let us know if any files need to be copied
        my $filesCopied = 0;

        # open the theme dir for reading
        opendir GBLTHEMEDIR, "$gblThemeDir/$opts{theme}" or
                die "Cannot open $gblThemeDir/$opts{theme}: $!\n";

        # get the list of files from that dir (except for . and ..)
        # prepend the theme dir back on to the filename as well
        my @themeFileList = map "$gblThemeDir/$opts{theme}/$_", grep !/^\.\.?$/, readdir GBLTHEMEDIR;

        # close the theme dir
        closedir GBLTHEMEDIR;

	my $dieMsg = "";
        # see if we need to copy any files
        foreach my $file (@themeFileList) {
    
            # We don't want to copy the standard theme files or any directories
            # They're not needed
            if (!-d $file && !($file =~ /$indexTmpl/) && !($file =~ /$slideTmpl/) && !($file =~ /$infoTmpl/) && !($file =~ /$opts{theme}\.theme/)) {
    
                # make sure the themeDir is created.
                if (!-d $themeDir) {
                    $dieMsg = "Cannot create the directory '$themeDir'.\n";
                    mkdir "$themeDir",0755 or die "$dieMsg : $!\n";
                }
    
                print "Copying the necessary theme files\n" if !$filesCopied;
                $filesCopied = 1; # we only want to print above message once
    
                # copy the file to the themeDir
                $dieMsg="Cannot copy $file to $themeDir\n";
                copy "$file","$themeDir" or die "$dieMsg: $!\n";
            }
        }
    
        # copy the thumb,slide and theme dir to the web-dir.
        # we won't do this if the web-dir is "." or the -uo or -lo opts are set
        if ($opts{wd} ne "." && !$opts{uo} && !$opts{lo}) { 
            # remove the web-dir first to prevent stale files
            if (-d $opts{wd}) {
                rmtree("$opts{wd}",0,0)
            }
    
            # create the output directory for the gallery if need be
            $dieMsg = "Cannot create the directory '$opts{wd}'.\n";
            mkdir "$opts{wd}",0755 or die "$dieMsg : $!\n";
        
            print "Copying the files to '$opts{wd}'\n";
            foreach my $dirToCopy ($thumbDir, $slideDir, $themeDir) {
    
                # if we need to copy that directory, do so
                if (-d $dirToCopy) {
                    # make the new dir
                    $dieMsg="Cannot create the directory '$opts{wd}/$dirToCopy'.\n";
                    mkdir "$opts{wd}/$dirToCopy",0755 or die "$dieMsg : $!\n";
    
                    # copy each file from that dir
                    foreach my $file (glob "$dirToCopy/*") {
                        $dieMsg="Cannot copy $file to $opts{wd}/$dirToCopy\n";
                        copy $file,"$opts{wd}/$dirToCopy" or die "$dieMsg: $!\n";
                    }
                }
            }
            # move all the html files
            foreach my $file (glob "*$indexExt") {
                $dieMsg = "Cannot move $file to $opts{wd}/$file\n";
                move "$file","$opts{wd}/$file" or die "$dieMsg $!\n";
            }
        }
    }

    # debug - print out the images and descriptions.
    if ($opts{d} >= 5) {
        print "--------------------------\n";
        print "Album Title Bar: $albumInfo->{titlebar}\n";
        print "Album Title: $albumInfo->{title}\n";
        print "Album Header: $albumInfo->{header}\n";
        print "Album Footer: $albumInfo->{footer}\n";
        print "Album Index Files: $albumInfo->{numPages}\n";
        for my $i (0 .. $#{$albumInfo->{images}}) {
            print "--------------------------\n";
            print "images[$i]{file}: <$albumInfo->{images}[$i]->{file}>\n";
            print "images[$i]{desc}: <$albumInfo->{images}[$i]->{desc}>\n";
            print "images[$i]{size}: <$albumInfo->{images}[$i]->{size}>\n";
            print "images[$i]{width}: <$albumInfo->{images}[$i]->{width}>\n";
            print "images[$i]{height}: <$albumInfo->{images}[$i]->{height}>\n";
            print "images[$i]{thumb}: <$albumInfo->{images}[$i]->{thumb}>\n";
            print "images[$i]{thumbx}: <$albumInfo->{images}[$i]->{thumbx}>\n";
            print "images[$i]{thumby}: <$albumInfo->{images}[$i]->{thumby}>\n";
            print "images[$i]{slide}: <$albumInfo->{images}[$i]->{slide}>\n";
            print "images[$i]{slidex}: <$albumInfo->{images}[$i]->{slidex}>\n";
            print "images[$i]{slidey}: <$albumInfo->{images}[$i]->{slidey}>\n";
            print "images[$i]{slidekb}: <$albumInfo->{images}[$i]->{slidekb}>\n";
            if ($#{$albumInfo->{images}[$i]->{exif}} > 0) {
                for my $j (0 .. $#{$albumInfo->{images}[$i]->{exif}}) {
                    print "  $j: $albumInfo->{images}[$i]->{exif}->[$j]{field} : ";
                    print "  $albumInfo->{images}[$i]->{exif}->[$j]{val}\n";
                }
            }
        }
    }

    # change back to our starting dir.
    die "Can't cd to $startDir $!\n" unless chdir $startDir;

}
print "\n$progName has finished processing\n";
exit 0;


########################### [ Functions below ] ###############################
# checkSiteInstall - check to make sure the site is properly configured to work
# with jigl.
#
# Checks for the environment variable HOME.
# Checks to see if ImageMagick is installed.
#
# returns: The version of ImageMagick
#
# Sets the array reference to be the version of ImageMagick we have.
# There is output differences in the 'identify' program we need to consider
# which is why we need this.
#
sub checkSiteInstall {
   # check to see if the $HOME environment variable is set.
   # exit with an ERROR if it's not.
   if (!(defined $ENV{HOME})) {
       print "ERROR: The HOME environment variable has not been set!\n";
       print "       Please set this so jigl knows where to check for default settings.\n\n";
       exit 1;
   }

   # check to see if ImageMagick is installed
   # exit with an error if it can't be found.
   my $tmp = qx/$imgInfoProg/;    # run the 'identify' prog.
   if ($? == -1) {
       print "ERROR: ImageMagick could not be found!.\n";
       print "       Please make sure the ImageMagick tools are in your path!\n\n";
       exit 1;
   }
   # pull out the version field from a valid response
   my @tmpArr = split /\n/,$tmp;       # split on new line
   chop @tmpArr;                       # chop any remaining new line
   my @lineArr = split / /,$tmpArr[0]; # split up the first line of the output
   return split /[.]/,$lineArr[2];     # split and return the version field X.y.z

}

###########################################################
# getWatermarkProg - determine what program we have that can watermark.
# older versions of ImageMagick use the program 'combine'. Newer versions
# use 'composite'. We'll check and see which one you have installed.
#
sub getWatermarkProg {

    my $prog = "";

    # check for composte first
    if (open CHECK, "composite 2>&1|") {
        if (<CHECK> =~ /imagemagick/i) { $prog = "composite"; }
        close CHECK;
    } elsif (open CHECK, "combine 2>&1|") {
        if (<CHECK> =~ /imagemagick/i) { $prog = "combine"; }
        close CHECK;
    }

    if ($prog eq "") { $prog = "none";}

    return $prog;
}

###########################################################
# getDirs - get the list of directories we are going to run the program on.
#
# If no directories are given on the command line then we assume the
# current directory.
#
# Returns a list.
#
sub getDirs {
    # save the ARGV option because the GetOptions function will modify
    # it and we need it intact for later.
    my @tmpArgv = @ARGV;
    my @tmpDirs = ();

    # call getCmdOpts, but we don't want the output, just the resulting
    # ARGV list.
    &getCmdOpts ({});

    # check to see if any dirs were on the cmdline or not.
    if ($#ARGV == -1) {
        @tmpDirs = (".");
    } else {
        @tmpDirs = @ARGV;
    }

    # retrore the orginal args
    @ARGV = @tmpArgv;

    return @tmpDirs;
}

###########################################################
# recursiveDirList - return an array of all the sub directories of
# the passed in argument.
#
# arguments:
# optsSys - default system options
# rd - root directory to recurse on.
# dl - an empty list used to store the resultant directory list.
# 
# returns a list of the sub directories.
# The initial directory is NOT included in the result. 

# This function also omits the following directories:
# ., ..,  slides, thumbs, theme and web.
#
#
sub recursiveDirList {
    my ($rd,@dl) = @_;

    # open this directory
    my $d = new DirHandle $rd;

    if (defined $d) {
        # while the directory can be read
        while (defined($_ = $d->read)) {
            # we want all dirs except ., ..,  slides, thumbs, theme and web.
            if ((-d "$rd\/$_") && $_ ne "." && $_ ne ".." && $_ ne $slideDir && $_ ne $thumbDir && $_ ne $themeDir && $_ ne $optsSys{wd}) { 
                push @dl,"$rd\/$_"; # add this dir to our list
                push @dl,&recursiveDirList("$rd\/$_",()); # check for subdirs
            }
        }
    }
    return @dl;
}

###########################################################
# setSystemOpts - setup the system-wide option defaults
#
# returns a hash which contains all the option and value pairs
# the key values MUST be the same as the short option name!!
#
sub setSystemOpts {
    return ("cg"=>"0",   # create-gallerydat
            "uec"=>"0",  # use-exif-comment
            "rs"=>"a",   # replace-spaces (default ask)
            "ut"=>"0",   # update-templates
            "ft"=>"0",   # force-thumb
            "fs"=>"0",   # force-slide
            "it"=>"",    # index-title
            "iw"=>"5",   # index-width
            "ir"=>"0",   # index-row
            "skb"=>"1",  # slide-kbsize
            "sxy"=>"1",  # slide-xysize
            "uo"=>"0",   # use-original
            "lo"=>"0",   # link-original
            "aro"=>"0",  # auto-rotate-originals
            "gs"=>"1",   # generate-slides
            "gi"=>"1",   # generate-info
            "sy"=>"480", # slideY
            "sx"=>"0",   # slideX
            "sle"=>"0",  # slide-long-edge
            "ty"=>"75",  # thumbY
            "tx"=>"0",   # thumbX
            "tle"=>"0",  # thumb-long-edge
            "iy"=>"240", # infoY
            "ws"=>"0",             # watermark-slide
            "wf"=>"watermark.png", # watermark-file
            "wg"=>"southeast",     # watermark-gravity
            "gb"=>"0",                # go-back
            "gbs"=>"Go Back",         # go-back-string
            "gburl"=>"../index.html", # go-back-url
            "theme"=>"default", # theme
            "wd"=>"web",   # web-dir
            "r"=> "0",     # recurse
            "h"=> "0",     # display help
            "v"=> "0",     # display version
            "d"=> "0",     # debug level
	    "x"=> ".html", # file extension
           );
}

###########################################################
# getRCOpts - get any options from the users jigl.opts file.
# There may be comments in the file (line starting with '#')
# Collect all option lines
#
# returns a hash
sub getRCOpts {

    # check to see if the rc file exists.
    if (-e $jiglRCFile) {
        print "Found \'$jiglRCFile\' -  Parsing options.\n";
    } else {
        print "No \'$jiglRCFile\' resource file found.\n";
        return ();
    }
    open RCFILE, "<$jiglRCFile" or die "Cannot open \'$jiglRCFile\'\n";

    # store the argv array temporarily
    my @tmpARGV = @ARGV;

    # get the options from the file and run them through the command line
    # option checker the ensure validity.
    my $line = "";
    while (<RCFILE>) {
	chomp;
        if ($_ =~ /^#/) {
            # skip - line is not an option
        } elsif ($_ =~ /^[ ]*$/) {
            # skip - line is blank
        } else {
            $line .= " ".$_;
        }
    }
    close RCFILE; # close the rc file

    $line =~ s/^ *//;		# remove initial blanks
    @ARGV = &shellwords($line); # move out options in the ARGV variable
    my %opts = getCmdOpts({}); # return a nice hash of options
    @ARGV = @tmpARGV;          # restore the original ARGV array.

    # return the options hash for the RC file
    return %opts;
}

###########################################################
# cgetGalOpts - get any options that are stored in gallery.dat
# Any line that starts with "GAL-OPTIONS" is considered an option argument
# and will be used.
#
# returns a hash
sub getGalOpts {

    # check to see if the gallery.dat file exists.
    if (-e $galDatFile) {
        print "Found \'$galDatFile\' - Parsing options.\n";
    } else {
        print "No \'$galDatFile\' resource file found.\n";
        return ();
    }
    open DATFILE, "<$galDatFile" or die "Cannot open \'$galDatFile\'\n";

    # store the argv array temporarily
    my @tmpARGV = @ARGV;

    # get the options from the file and run them through the command line
    # option checker the ensure validity.
    my @tmpArr = (); # temporary array
    while (<DATFILE>) {
       # build up an array of args found in the gallery.dat file
       if ($_ =~ /^GAL-OPTIONS/) {
          chop $_;                   # strip off that pesky newline
          my @tmpOpt = &shellwords($_); # make array of the options line
          shift @tmpOpt;             # remove the tag from the array
          push @tmpArr,@tmpOpt;      # add our new option to the array
       }
    }
    close DATFILE; # close the gallery.dat file

    @ARGV = @tmpArr;                # move our options to the ARGV variable
    my %opts = getCmdOpts({}); # retrun a nice hash of options
    @ARGV = @tmpARGV;          # restore the original ARGV array.

    # return the options hash for the gallery.dat file
    return %opts;
}

###########################################################
# getCmdOpts - get the command line options
#
# uses the system default hash to populate the command line hash. Any new
# options that were passed from the command line will be updated here.
# returns a new hash that contains all the options for the program.
#
# When the procedure is done the value of @ARGV will have changed. All of
# the options will have been removed leaving just the remaining, non-options,
# left. In our case these will be the directories we want to run the program
# on.
#
sub getCmdOpts {
    # populate optsCmd with the hash passed in. This way we don't have to
    # predefine all the keys for the hash again.
    my (%opts) = %{$_[0]};

    # get the options and store them in the optsCmd hash.
    &printUsage unless GetOptions(\%opts, 'cg|create-gallerydat',
               'uec|use-exif-comment!',
               'rs|replace-spaces=s',
               'ut|update-templates!',
               'ft|force-thumb!',
               'fs|force-slide!',
               'it|index-title=s',
               'iw|index-width=i',
               'ir|index-row=i',
               'skb|slide-kbsize!',
               'sxy|slide-xysize!',
               'uo|use-original!',
               'lo|link-original!',
               'aro|auto-rotate-originals!',
               'gs|generate-slides!',
               'gi|generate-info!',
               'sy|slideY=i',
               'sx|slideX=i',
               'sle|slide-long-edge=i',
               'ty|thumbY=i',
               'tx|thumbX=i',
               'tle|thumb-long-edge=i',
               'iy|infoY=i',
               'ws|watermark-slides!',
               'wf|watermark-file=s',
               'wg|watermark-gravity=s',
               'gb|go-back!',
               'gbs|go-back-string=s',
               'gburl|go-back-url=s',
               'theme=s',
               'wd|web-dir=s',
               'r|recurse',
               'h|help',
               'v|version',
               'd|debug=i',
		'x|ext=s',
              );

    # return the optsCmd hash
    return %opts;
}

###########################################################
# checkOpts - check the validity of the options hash.
#
# Do bounds checking for options that require an argument.
# Print error and set option to default if an option is bad.
#
# return the new options hash
#
sub checkOpts {
    my (%opts)    = %{$_[0]}; # options to check
    my (%optsSys) = %{$_[1]}; # system defaults

    # bounds check the options
    # --replace-spaces
    if ((defined $opts{rs}) and !($opts{rs} =~ /^[ayn]$/i)) {
        print "Error: '$opts{rs}' is an invalid value to option --replace-spaces\n";
        print "  Valid values are [ayn] where 'a'=ask; 'y'=yes; 'n'=no\n";
        print "  Resetting option to default: '$optsSys{rs}'\n";
        $opts{rs} = $optsSys{rs};
    }
    # --index-width
    if ((defined $opts{iw}) and (($opts{iw} <= 0) or ($opts{iw} > 255))) {
        print "Error: '$opts{iw}' is an invalid value to option --index-width\n";
        print "  Valid values are 1 - 255\n";
        print "  Resetting option to default: '$optsSys{iw}'\n";
        $opts{iw} = $optsSys{iw};
    }
    # --index-row
    if ((defined $opts{ir}) and (($opts{ir} < 0) or ($opts{ir} > 255))) {
        print "Error: '$opts{ir}' is an invalid value to option --index-row\n";
        print "  Valid values are 0 - 255\n";
        print "  Resetting option to default: '$optsSys{ir}'\n";
        $opts{ir} = $optsSys{ir};
    }
    # --slideY
    if (defined $opts{sy}) {
        if ($opts{sy} > 0) {
            # reset slideX and slide-long-edge so they don't cause problems
            $opts{sx} = 0;
            $opts{sle} = 0;
        } elsif ($opts{sy} == 0 and ((defined $opts{sx} and $opts{sx} > 0) or (defined $opts{sle} and $opts{sle} > 0))) {
            # this is an OK condition - we just want to make sure one of the
            # other scale options is defined and greater than 0 before we
            # allow this scale option to be 0.
        } else {
            print "Error: '$opts{sy}' is an invalid value to option --slideY\n";
            print "  Minimum value is 1 unless one of the other scale options are set\n  Which they're not.\n";
            print "  Resetting option to default: '$optsSys{sy}'\n";
            $opts{sy} = $optsSys{sy};

            print "  Resetting other slide scale options to their defaults\n";
            # reset slideX and slide-long-edge so they don't cause problems
            $opts{sx} = $optsSys{sx};
            $opts{sle} = $optsSys{sle};
        }
    }
    # --slideX
    if (defined $opts{sx}) {
        if ($opts{sx} > 0) {
            # reset slideY and slide-long-edge so they don't cause problems
            $opts{sy} = 0;
            $opts{sle} = 0;
        } elsif ($opts{sx} == 0 and ((defined $opts{sy} and $opts{sy} > 0) or (defined $opts{sle} and $opts{sle} > 0))) {
            # this is an OK condition - we just want to make sure one of the
            # other scale options is defined and greater than 0 before we
            # allow this scale option to be 0.
        } else {
            print "Error: '$opts{sx}' is an invalid value to option --slideX\n";
            print "  Minimum value is 1 unless one of the other scale options are set\n  Which they're not.\n";
            print "  Resetting option to default: '$optsSys{sx}'\n";
            $opts{sx} = $optsSys{sx};

            print "  Resetting other slide scale options to their defaults\n";
            # reset slideY and slide-long-edge so they don't cause problems
            $opts{sy} = $optsSys{sy};
            $opts{sle} = $optsSys{sle};
        }
    }
    # --slide-long-edge
    if (defined $opts{sle}) {
        if ($opts{sle} > 0) {
            # reset slideX and slideY so they don't cause problems
            $opts{sx} = 0;
            $opts{sy} = 0;
        } elsif ($opts{sle} == 0 and ((defined $opts{sx} and $opts{sx} > 0) or (defined $opts{sy} and $opts{sy} > 0))) {
            # this is an OK condition - we just want to make sure one of the
            # other scale options is defined and greater than 0 before we
            # allow this scale option to be 0.
        } else {
            print "Error: '$opts{sle}' is an invalid value to option --slide-long-edge\n";
            print "  Minimum value is 1 unless one of the other scale options are set\n  Which they're not.\n";
            print "  Resetting option to default: '$optsSys{sle}'\n";
            $opts{sle} = $optsSys{sle};

            print "  Resetting other slide scale options to their defaults\n";
            # reset slideX and slide-long-edge so they don't cause problems
            $opts{sx} = $optsSys{sx};
            $opts{sy} = $optsSys{sy};
        }
    }
    # --thumbY
    if (defined $opts{ty}) {
        if ($opts{ty} > 0) {
            # reset thumbX and thumb-long-edge so they don't cause problems
            $opts{tx} = 0;
            $opts{tle} = 0;
        } elsif ($opts{ty} == 0 and ((defined $opts{tx} and $opts{tx} > 0) or (defined $opts{tle} and $opts{tle} > 0))) {
            # this is an OK condition - we just want to make sure one of the
            # other scale options is defined and greater than 0 before we
            # allow this scale option to be 0.
        } else {
            print "Error: '$opts{ty}' is an invalid value to option --thumbY\n";
            print "  Minimum value is 1 unless one of the other scale options are set\n  Which they're not.\n";
            print "  Resetting option to default: '$optsSys{ty}'\n";
            $opts{ty} = $optsSys{ty};

            print "  Resetting other thumb scale options to their defaults\n";
            # reset thumbX and thumb-long-edge so they don't cause problems
            $opts{tx} = $optsSys{tx};
            $opts{tle} = $optsSys{tle};
        }
    }
    # --thumbX
    if (defined $opts{tx}) {
        if ($opts{tx} > 0) {
            # reset thumbY and thumb-long-edge so they don't cause problems
            $opts{ty} = 0;
            $opts{tle} = 0;
        } elsif ($opts{tx} == 0 and ((defined $opts{ty} and $opts{ty} > 0) or (defined $opts{tle} and $opts{tle} > 0))) {
            # this is an OK condition - we just want to make sure one of the
            # other scale options is defined and greater than 0 before we
            # allow this scale option to be 0.
        } else {
            print "Error: '$opts{tx}' is an invalid value to option --thumbX\n";
            print "  Minimum value is 1 unless one of the other scale options are set\n  Which they're not.\n";
            print "  Resetting option to default: '$optsSys{tx}'\n";
            $opts{tx} = $optsSys{tx};

            print "  Resetting other thumb scale options to their defaults\n";
            # reset thumbY and thumb-long-edge so they don't cause problems
            $opts{ty} = $optsSys{ty};
            $opts{tle} = $optsSys{tle};
        }
    }
    # --thumb-long-edge
    if (defined $opts{tle}) {
        if ($opts{tle} > 0) {
            # reset thumbY and thumbX so they don't cause problems
            $opts{ty} = 0;
            $opts{tx} = 0;
        } elsif ($opts{tle} == 0 and ((defined $opts{ty} and $opts{ty} > 0) or (defined $opts{tx} and $opts{tx} > 0))) {
            # this is an OK condition - we just want to make sure one of the
            # other scale options is defined and greater than 0 before we
            # allow this scale option to be 0.
        } else {
            print "Error: '$opts{tle}' is an invalid value to option --thumb-long-edge\n";
            print "  Minimum value is 1 unless one of the other scale options are set\n  Which they're not.\n";
            print "  Resetting option to default: '$optsSys{tle}'\n";
            $opts{tle} = $optsSys{tle};

            print "  Resetting other thumb scale options to their defaults\n";
            # reset thumbY and thumbX so they don't cause problems
            $opts{ty} = $optsSys{ty};
            $opts{tx} = $optsSys{tx};
        }
    }
    # --infoY
    if ((defined $opts{iy}) and $opts{iy} <= 0) {
        print "Error: '$opts{iy}' is an invalid value to option --infoY\n";
        print "  Minimum value is 1\n";
        print "  Resetting option to default: '$optsSys{iy}'\n";
        $opts{ty} = $optsSys{ty};
    }
    # --watermark-gravity
    if ((defined $opts{ws}) and (defined $opts{wg})) {
        if (($opts{ws}) && ("north south east west northeast northwest southeast southwest" !~ /$opts{wg}/i)) {
            print "Error: '$opts{wg}' is an invalid value to option --watermark-gravity\n";
            print "  Valid options are: north, south, east, west\n";
            print "  northeast, northwest, southeast, and southwest\n";
            print "  Resetting option to default: '$optsSys{wg}'\n";
            $opts{wg} = $optsSys{wg};
        }
    }
    # --watermark-file
    if ((defined $opts{ws}) and (defined $opts{wf})) {
        if ($opts{ws} && !(-e $opts{wf})) {
            print "Error: Cannot find the watermark file: '$opts{wf}'\n";
            print "   Turning OFF Watermarking of the slides!\n";
            $opts{ws} = 0;
        }
    }
    # --ext
    if (defined $opts{'x'}) {
	$indexExt = $opts{'x'};
    }
    # --theme
    if (defined $opts{theme}) {
        my $themeFile    = $opts{theme} . ".theme"; # full theme file name
        my $gblThemeFile = $gblThemeDir . "/" . $opts{theme} . "/" . $themeFile;

        # reset to default if theme file doesn't exists.
        if (!(-e $gblThemeFile) && $opts{theme} ne $optsSys{theme}) {
            print "Error: Cannot find the theme file: '$themeFile'\n"; 
            print "   Make sure it's in the directory '" . $gblThemeDir . "/" . $opts{theme} . "'\n";
            print "   Using the default theme.\n";
            $opts{theme} = $optsSys{theme};
        }

        # re-assign the global template files if the theme defines its own
        # index template
        my $tmpTmpl   = $gblThemeDir ."/". $opts{theme} ."/". $indexTmpl;
        $gblIndexTmpl = $tmpTmpl if (-e $tmpTmpl);

        # Javascript file
        $tmpTmpl      = $gblThemeDir ."/". $opts{theme} ."/". $jsfile;
        $gblJsFile = $tmpTmpl if (-e $tmpTmpl);

        # slide template
        $tmpTmpl      = $gblThemeDir ."/". $opts{theme} ."/". $slideTmpl;
        $gblSlideTmpl = $tmpTmpl if (-e $tmpTmpl);

        # info template
        $tmpTmpl      = $gblThemeDir ."/". $opts{theme} ."/". $infoTmpl;
        $gblInfoTmpl  = $tmpTmpl if (-e $tmpTmpl);
    }

    # do any options specific processing

    return %opts;
}

###########################################################
# mergeOpts - merge the various options arrays into one single array.
#
# merger order is:
# system options -> ~/.jigl/jigl.opts -> gallery.dat -> command line options.
#
# return a new hash with the final options defined
#
sub mergeOpts {
    my ($sys,$rc,$gal,$cmd) = @_;

    # start with the system options and merge the rc options over them
    my %opts = ();
    foreach my $key (keys %$sys) {
        if (defined $$rc{$key}) {
            # use the rc option
            $opts{$key} = $$rc{$key};
        } else {
            # keep the system default
            $opts{$key} = $$sys{$key};
        }
    }

    # now merge the gallery options over the these
    foreach my $key (keys %opts) {
        if (defined $$gal{$key}) {
            # use the gallery option
            $opts{$key} = $$gal{$key};
        }
    }

    # finally merge the command line options over the these
    foreach my $key (keys %opts) {
        if (defined $$cmd{$key}) {
            # use the command line option
            $opts{$key} = $$cmd{$key};
        }
    }

    # debug - print all the options and when the got set.
    if ($opts{d} >= 2) {
        print "\nFinal Options:\nKey:\tSys\tRC\tGal\tCmd\tOpts\n";
        foreach my $key (keys %$sys) {
            print "$key:\t$$sys{$key}\t";
            if (defined $$rc{$key}) {
                print "$$rc{$key}\t"
            } else {
                print "--\t";
            }
            if (defined $$gal{$key}) {
                print "$$gal{$key}\t"
            } else {
                print "--\t";
            }
            if (defined $$cmd{$key}) {
                print "$$cmd{$key}\t"
            } else {
                print "--\t";
            }
            print "$opts{$key}\n";
        }
        print "\n";
    }

    return %opts;
}

###########################################################
# genAlbumInfo - generate the master array containing info about the album.
#
# options that concern this function:
# -cg (--create-gallerydat)
# -rs (--replace-spaces)
# -aro (--auto-rotate-originals)
#
# -cg option not set
# ------------------
# gallery.dat file exists:
# It will parse it and return a list of hashes containing the image file
# names and descriptions. The gallery.dat file will NOT be written to.
#
# gallery.dat file does not exists:
# It will simply return the list of hashes with the file names filled in
# and the descriptions empty. NO gallery.dat file will be created!
#
# -cg option set
# --------------
# gallery.dat file exists OR gallery.dat file does not exist:
# It will create a NEW gallery.dat file and return an empty array.
# That means if the gallery.dat file exists, any options, file descriptions
# or file ordering will be LOST!
#
# --------------------------
# returns a reference to a hash.
# --------------------------
# The hash contains the title of the page, the header and footer strings
# and a reference to an array of images.
# The array of images is ordered in the way the files are listed in
# gallery.dat.  If no gallery.dat file is found, it will store the files
# in the order that glob retuned them.
#
sub genAlbumInfo {
    my (%opts)  = %{$_[0]};  # options hash
    my ($dir)   = $_[1];     # the directory we're working on
    my $href    = {};        # temp hash reference
    my $aInfo   = &newAlbumInfo; # album info hash
    my @tmpArr = ();         # temp array
    my $picCnt = 0;          # count of valid pictures
    my $skipCnt = 0;         # count of skipped pictures
    my $filesWithSpaces = 0; # number of files with spaces

    print "Retrieving file info from directory \'$dir\'\n" if $opts{d};

    # if we have a gallery.dat file and we're not creating a new
    # gallery.dat file.
    if (-e $galDatFile && !$opts{cg}) {
        # read the gallery.dat file and update the albumInfo hash
        open GALFILE, "<$galDatFile" or die "Cannot open \'$galDatFile\'\n";

        print "Found \'$galDatFile\' - Retrieving file list.\n";

        while (<GALFILE>) {
            if ($_ =~ /^#/) {
                # skip - line is a comment
            } elsif ($_ =~ /^[ ]*$/) {
                # skip - line is blank
            } elsif ($_ =~ /^GAL-OPTIONS/) {
                # skip - line contains gallery options
            } elsif ($_ =~ /^INDEX/) {
                # we have some index option
                chop $_;

                # read in the index tag and it's value and
                # trim off the whitespace
                my ($tag,$val) = split /----/,$_;
                &trimWS($tag); &trimWS($val);
                if ($tag =~ /index-titlebar/i) {
                    $aInfo->{titlebar} = $val;
                } elsif ($tag =~ /index-title/i) {
                    $aInfo->{title} = $val;
                } elsif ($tag =~ /index-header/i) {
                    $aInfo->{header} = $val;
                } elsif ($tag =~ /index-footer/i) {
                    $aInfo->{footer} = $val;
                } else {
                    print "Warning: Invalid option found in $galDatFile. <$tag>\n";
                }
            } else {
                # we have a filename and description line
                $href = &newImgInfo; # create a new image info hash
                chop $_;             # get rid of that pesky newline

                # read in the file name and descr
                my ($file,$desc) = split /----/,$_;

                # skip file if it doesn't exist
                if (!-e trimWS($file)) {
                    print "Skipping nonexistent image file: $file\n";
                    $skipCnt++;
                    next;
                }

                # stuff the file and desc into the hash
                $href->{file} = trimWS($file);
                $href->{desc} = trimWS($desc);

                # rotate the original before we get it's size,X,and Y info.
                &rotateOrig($href->{file}) if $opts{aro};

                # get the files size and X,Y info
                @tmpArr = &getImgInfo($href->{file});
                $href->{size} = $tmpArr[0];
                $href->{width} = $tmpArr[1];
                $href->{height} = $tmpArr[2];

                # push the new image into the array if the image is valid
                if ($href->{size} ne "") {
                    push @{$aInfo->{images}},$href;
                    # my $spaceCnt = () = $file =~ m/ /g;
                    $filesWithSpaces++ if ($href->{file} =~ / /);
                    $picCnt++;
                } else {
                    print "Skipping invalid image file: $file\n";
                    $skipCnt++;
                }
            }
        }
        close GALFILE; # close the gallery.dat file
        print "$picCnt of " . ($picCnt + $skipCnt) . " image files found in $galDatFile were valid.\n";

    } else {
        # no gallery.dat file found - just using image files found in dir.
        # get a list of files to work on
        my @files = glob($fileTypeStr);

        if ($opts{cg}) {
            print "Creating a new $galDatFile. Checking for files in directory.\n";
        } else {
            print "No $galDatFile file found. Checking for files in directory.\n";
        }

        # stuff each file into the hash and push it on the list
        foreach my $file (@files) {
            # create a new imgInfo structure and fill in it's name
            $href = &newImgInfo;
            $href->{file} = trimWS($file);

            # rotate the original before we get it's size,X,and Y info.
            &rotateOrig($href->{file}) if $opts{aro};

            # get the files size and X,Y info
            @tmpArr = &getImgInfo($href->{file});
            $href->{size} = $tmpArr[0];
            $href->{width} = $tmpArr[1];
            $href->{height} = $tmpArr[2];

            # push the new image into the array if the image is valid
            if ($href->{size} ne "") {
                push @{$aInfo->{images}},$href;
                $filesWithSpaces++ if ($href->{file} =~ / /);
                $picCnt++;
            } else {
                print "Skipping invalid image file: $file\n";
                $skipCnt++;
            }
        }

        print "$picCnt of " . ($picCnt + $skipCnt) ." image files found in the directory were valid.\n";

    }

    # figure out how many index pages need to be generated (zero based)
    my $numPages = 0;
    if ($opts{ir} > 0 && (($opts{iw} * $opts{ir}) <= $#{$aInfo->{images}})) {
        $numPages = int($#{$aInfo->{images}} / ($opts{iw} * $opts{ir}));
    }
    $aInfo->{numPages} = $numPages;
 
    # replace spaces in filenames with underscores
    &convertFileNames($aInfo,$opts{rs}) if $filesWithSpaces;

    # get the exif info for each image
    &genExifInfo(\%opts,$aInfo);

    # are we creating a go back link? If so, prepend it to the header but
    # only if the gburl is not already in the header.
    if ($opts{gb} && ($aInfo->{header} !~ m/<a href=\"$opts{gburl}\">/)) {
        my $gbStr = "<a href=\"$opts{gburl}\">$opts{gbs}</a><br/>" . $aInfo->{header};
        $aInfo->{header} = $gbStr;
    }

    # create a new gallery.dat file from the files hash and return
    if ($opts{cg}) {
        &createNewGalDat(\%opts, $aInfo);
        return ();
    }

    return $aInfo;
}

###########################################################
# rotateOrig - auto rotate the original images
#
# input: image file to rotate
#
sub rotateOrig {
    my ($file) = @_;
    my $msgPad = "                         "; # 25 spaces

    print "Rotating image: $file $msgPad\r";
    qx{$exifProg -autorot "$file" 2>/dev/null};
}

###########################################################
# convertFileNames - replace spaces with underscores in filenames
#
# Input: albumInfo reference and -rs option value
#
sub convertFileNames {
    my ($albumInfo,$opt) = @_;
    my $yn = "";     # temp yes/no variable
    my $dieMsg = ""; # message to send to die

    # while we don't have a yes or no answer from the user
    while (!($opt =~ /^[yn]$/i)) {
        print "\n----------------------------------------------------\n";
        print "There were spaces detected in some of the filenames.\n";
        print "Spaces are EVIL, hard to work with, can break programs and\n";
        print "are a pain in the ass to deal with in HTML code.\n";
        print "It's recommended that you convert the spaces to underscores\n";
        print "in the filenames.\n";
        print "You can set the -rs|--replace-spaces option and you'll never\n";
        print "see this message again.\n";
        print "\n";
        print "Do you want jigl to convert the offending file names?\n";
        print "(y) or n > ";
        $yn = <STDIN>; # get the input from the user
        chop $yn;
        $yn = "y" if $yn eq ""; # if they hit enter, make it a "y"

        # if $yn is a y or n, set opt to it and quit the loop.
        $opt = $yn if $yn =~ /^[yn]$/i;
    }

    # if we had a yes response, convert the filenames
    if ($opt eq "y") {
        print "Converting spaces in filenames to underscores.\n";
        # check each filename
        my $orig = ""; # original file name
        my $new  = ""; # new file name
        for my $i (0 .. $#{$albumInfo->{images}}) {
            my $orig = $albumInfo->{images}[$i]->{file};
            $albumInfo->{images}[$i]->{file} =~ s/ /_/g;
            my $new = $albumInfo->{images}[$i]->{file};
            # only move the file if it's different
            if (!($orig eq $new)) {
                $dieMsg = "Cannot move $orig to $new\n";
                move $orig,$new or die "$dieMsg $!\n";
            }
        }

        # change the filenames in the gallery.dat file too.
        if (-e $galDatFile) {
            print "Updating $galDatFile\n";

            # move the gallery.dat file to a temp file
            my $tmpGalDatFile = "tmp-$galDatFile";
            my $dieMsg = "Cannot move $galDatFile to $tmpGalDatFile!\n";
            move $galDatFile,$tmpGalDatFile or die "$dieMsg$!\n";

            # open for temp file for reading, original file for writing
            open RFILE, "<$tmpGalDatFile" or die "Cannot open \'$tmpGalDatFile\'\n";
            open WFILE, ">$galDatFile" or die "Cannot open \'$galDatFile\'\n";

            # read in each line and change if need be
            while (<RFILE>) {
                if (($_ =~ /^#/) or ($_ =~ /^$/) or ($_ =~ /^GAL-OPTIONS/) or ($_ =~ /^INDEX/)) {
                    # just write - line is a comment,blank or contains options
                    print WFILE $_;
                } else {
                    # we have a filename and description line
                    chop $_; # get rid of that pesky newline

                    # read in the file name and descr
                    my ($file,$desc) = split /----/,$_;
                    trimWS($file);    # trim whitespace
                    trimWS($desc);    # trim whitespace
                    $file =~ s/ /_/g; # replace the spaces with underscores
 
                    # write the line back to the file
                    print WFILE "$file ---- $desc\n";
                }
            }
            # close the files
            close RFILE;
            close WFILE;

            # delete the temp file
        }
    }
}

###########################################################
# getImgInfo - takes file name and returns an array with the
# size, width, and height of the image (in that order).
#
sub getImgInfo {
    my ($file) = @_;
    my @retArr = ();
    my $badImgMsg = "identify:";

    # count the number of spaces in the filename for offset reasons
    my $spaceCnt = () = $file =~ m/ /g;

    # get file size, and XxY info
    my $line = qx/$imgInfoProg -ping "$file" 2>&1/;
    chop $line; # remove pesky new line

    # check to see if we had a bad file
    if ($line =~ m/$badImgMsg*/i) {
        # bad image found.
        # push empty values into the array to return
        push @retArr,"";
        push @retArr,"";
        push @retArr,"";

    } else {
        # pick out the XxY portion of the line
        my $xyLine = $1 if ($line =~ m/( [0-9]+x[0-9]+)/);
        my @xyArr  = split /x|[+]|[=>]/,$xyLine; # split up XxY+val+val
        my $width  = &trimWS($xyArr[0]);
        my $height = &trimWS($xyArr[1]);
        # get the size of the file - in bytes
        my $size = -s $file;
        # round (not trunc) the division to the nearest int
        # and add kb at the end
        $size = sprintf("%.0fkb",($size / 1024));

        # push the values into the array to return
        push @retArr,$size;
        push @retArr,$width;
        push @retArr,$height;
    }
    return @retArr;
}

###########################################################
# createNewGalDat - create a new gallery.dat file in the
# current directory from the list of valid filenames in the albumInfo
#
sub createNewGalDat {
    my (%opts) = %{$_[0]};
    my ($albumInfo) = $_[1];
    my $yn = "y"; # create galDatFile

    if (-e $galDatFile) {
        $yn = ""; # clear this option out so we can ask the user

        # while we don't have a yes or no answer from the user
        while (!($yn =~ /^[yn]$/i)) {
            print "\n----------------------------------------------------\n";
            print "You have called $progName with the --create-gallerydat option\n";
            print "$progName has detected that a $galDatFile already exists.\n";
            print "If you overwrite this file all current descriptions and\n";
            print "customizations will be LOST!!\n";
            print "\nWould you like to overwrite the current $galDatFile?\n";
            print "y or (n) > ";
            $yn = <STDIN>; # get the input from the user
            chop $yn;
            $yn = "n" if $yn eq ""; # if they hit enter, make it a "n"
        }
        print "----------------------------------------------------\n\n";
    }

    # if we wanted to
    if ($yn eq "y") {
        print "Creating $galDatFile\n";

        open(GALFILE,"> $galDatFile") || die "Cannot open \'$galDatFile\' $!\n";
        print GALFILE "# Options can be placed after GAL-OPTIONS tag.\n";
        print GALFILE "# They should be on one line and entered like they would\n";
        print GALFILE "# on the command line. e.g. GAL-OPTIONS -ft -fs -rs y\n";
        print GALFILE "GAL-OPTIONS\n";
        print GALFILE "#\n";
        print GALFILE "##############################################\n";
        print GALFILE "# Below are the index options with their values and\n";
        print GALFILE "# the file names and descriptions\n";
        print GALFILE "# All are seperated by '----' this MUST remain.\n";
        print GALFILE "# The file name and description must be on ONE line. The\n";
        print GALFILE "# description can contain html tags if desired.\n";
        print GALFILE "# You can change the order and it will be preserved when\n";
        print GALFILE "# you generate the index.html and slide pages.\n";
        print GALFILE "##############################################\n";
        print GALFILE "#\n";
        print GALFILE "INDEX-TITLEBAR ---- My Pictures\n";
        print GALFILE "INDEX-TITLE ---- My Pictures\n";
        print GALFILE "INDEX-HEADER ---- $albumInfo->{header}\n";
        print GALFILE "INDEX-FOOTER ----\n";
        print GALFILE "#\n";
        for my $i (0 .. $#{$albumInfo->{images}}) {
            print GALFILE "$albumInfo->{images}[$i]->{file} ---- $albumInfo->{images}[$i]->{desc}\n";
        }
        close GALFILE;
    } else {
        print "Skipping creation of $galDatFile\n";
    }
}

###########################################################
# genThumbs - generates thumbnail files
#
# input: a reference to the options hash
#        a reference to the albumInfo
#
# side effect: update the albumInfo with the name of the thumbnail image
#
sub genThumbs {
    my (%opts) = %{$_[0]};
    my ($albumInfo) = $_[1];
    print "Generating thumbnails\n";

    my $tmpFile = "";          # temp variable to hold image name
    my $tmpThumbFile = "";     # temp variable to hold thumbnail name
    my @tmpArr = ();           # temp array
    my $cmd  = "$scaleProg"; # cmd to run to scale images
    my $dieMsg = "";           # message to print if we die
    my $msgPad = "                         "; # 25 spaces
    my $genCnt = 0;            # number of thumbnails generated
    my $skipCnt = 0;           # number of thumbnails already existing

    # create the thumbnail directory if need be
    if (!(-d $thumbDir)) {
        print "The thumbnail directory: '$thumbDir' did not exist. Creating.\n";
        $dieMsg = "Cannot create the directory '$thumbDir'.\n";
        mkdir $thumbDir,0755 or die "$dieMsg : $!\n";
    }

    # generate thumbnail for each image
    for my $i (0 .. $#{$albumInfo->{images}}) {
        # get the name of the file and create the thumbnail filename
        # store the name of the thumbnail for this image in the albumInfo
        $tmpFile = $albumInfo->{images}[$i]->{file};
        $tmpThumbFile = "$thumbPrefix" . "$tmpFile";
        $albumInfo->{images}[$i]->{thumb} = $tmpThumbFile;

        # copy and scale if the thumbnail does not already exist or we are
        # forcing the generation of the thumbnails
        if ($opts{ft} or (!(-e $tmpThumbFile))) {
            # scale the image to the thumbnail size specs
            print "\r\(" . ($i+1) . "/" . ($#{$albumInfo->{images}}+1) . "\) Scaling $tmpThumbFile $msgPad";

            # if we're scaling the long-edge of the thumbnail, figure out
            # what side of the image needs to be scaled
            if ($opts{tle} > 0) {

                my $tmpY = $albumInfo->{images}[$i]->{height};
                my $tmpX = $albumInfo->{images}[$i]->{width};
                # height is greater
                if ($tmpY > $tmpX) {
                    # stuff the sle value into the ty option
                    $opts{ty} = $opts{tle};
                    $opts{tx} = 0;

                # either width is greater or they are equal.
                # either way, we can use the X value with out a problem
                } else {
                    # stuff the sle value into the tx option
                    $opts{tx} = $opts{tle};
                    $opts{ty} = 0;
                }
            }
            # y-scale: scale the thumb if it's Y height is greater than
            # the value of the ty option and ty != 0
            if ($opts{ty} > 0 and $albumInfo->{images}[$i]->{height} > $opts{ty}) {
                $cmd = "$scaleProg -scale x$opts{ty} -sharpen 5 \"$tmpFile\" \"$tmpThumbFile\"";
                $dieMsg = "\nCannot scale the thumbnail image! $tmpFile\n";
                system($cmd) == 0 or warn $dieMsg;

            # x-scale: scale the thumb if it's X width is greater than
            # the value of the tx option and tx != 0
            } elsif ($opts{tx} > 0 and $albumInfo->{images}[$i]->{width} > $opts{tx}) {
                $cmd = "$scaleProg -scale $opts{tx} -sharpen 5 \"$tmpFile\" \"$tmpThumbFile\"";
                $dieMsg = "\nCannot scale the thumbnail image! $tmpFile\n";
                system($cmd) == 0 or warn $dieMsg;

            # no-scale: image does not need to be scaled
            } else {
                $dieMsg = "Cannot copy \"$tmpFile\" to \"$tmpThumbFile\"\n";
                copy $tmpFile,$tmpThumbFile or die "$dieMsg $!\n";
            }

            # increment the generated count
            $genCnt++;
        } else {
            # increment the skipped count
            print "\r\(" . ($i+1) . "/" . ($#{$albumInfo->{images}} + 1) . "\) Skipping $tmpThumbFile $msgPad";
            $skipCnt++;
        }

        # get the files size and X,Y info for the slide
        my @tmpArr = &getImgInfo($albumInfo->{images}[$i]->{thumb});
        $albumInfo->{images}[$i]->{thumbkb} = $tmpArr[0];
        $albumInfo->{images}[$i]->{thumbx}  = $tmpArr[1];
        $albumInfo->{images}[$i]->{thumby}  = $tmpArr[2];
    }
    print "\r"; # move back to the start of the line
    print "$genCnt thumbnails generated. $msgPad\n" if $genCnt > 0;
    print "$skipCnt thumbnails skipped because they already existed.\n" if $skipCnt > 0;
    print "Finished generating thumbnail images.\n\n";
}

###########################################################
# genSlides - generates slide files
#
# input: a reference to the options hash
#        a reference to the albumInfo
#
# side effect: update the albumInfo with the name of the slide image
#              update the albumInfo with the size in kb of the slide image
#              update the albumInfo with the XxY dimensions of the slide image
#
sub genSlides {
    my (%opts) = %{$_[0]};
    my ($albumInfo) = $_[1];
    print "Generating slides\n";

    my $tmpFile = "";          # temp variable to hold image name
    my $tmpSlideFile = "";     # temp variable to hold slide name
    my $cmd  = "$scaleProg";   # cmd to run to scale images
    my $dieMsg = "";           # message to print if we die
    my $msgPad = "                         "; # 25 spaces
    my $genCnt = 0;            # number of thumbnails generated
    my $skipCnt = 0;           # number of thumbnails already existing
    my $tmpArr = ();           # temporary array

    # create the slide directory if need be
    if (!(-d $slideDir) && !($opts{uo})) {
        print "The slide directory: '$slideDir' did not exist. Creating.\n";
        $dieMsg = "Cannot create the directory '$slideDir'.\n";
        mkdir $slideDir,0755 or die "$dieMsg : $!\n";
    }

    # generate slide for each image
    for my $i (0 .. $#{$albumInfo->{images}}) {
        # get the name of the file and create the slide filename
        $tmpFile = $albumInfo->{images}[$i]->{file};
        $tmpSlideFile = "$slidePrefix" . "$tmpFile";

        # store the name of the slide for this image in the albumInfo
        if ($opts{uo}) {
            # if the use-originals option is used, we're not going to
            # create a slide
            $albumInfo->{images}[$i]->{slide} = $tmpFile;
        } else {
            # store the slide file if making slides
            $albumInfo->{images}[$i]->{slide} = $tmpSlideFile;
        }

        # scale the image if the slide does not already exist or we are
        # forcing the generation of the slides and we're not using the orig's
        if (($opts{fs} or (!(-e $tmpSlideFile))) && !($opts{uo})) {
            # scale the image to the slide size specs
            print "\r\(" . ($i+1) . "/" . ($#{$albumInfo->{images}}+1) . "\) Scaling $tmpSlideFile $msgPad";

            # if we're scaling the long-edge of the slide, figure out
            # what side of the image needs to be scaled
            if ($opts{sle} > 0) {

                my $tmpY = $albumInfo->{images}[$i]->{height};
                my $tmpX = $albumInfo->{images}[$i]->{width};
                # height is greater
                if ($tmpY > $tmpX) {
                    # stuff the sle value into the sy option
                    $opts{sy} = $opts{sle};
                    $opts{sx} = 0;

                # either width is greater or they are equal.
                # either way, we can use the X value with out a problem
                } else {
                    # stuff the sle value into the sx option
                    $opts{sx} = $opts{sle};
                    $opts{sy} = 0;
                }
            }
            # y-scale: scale the slide if it's Y height is greater than
            # the value of the sy option and sy != 0
            if ($opts{sy} > 0 and $albumInfo->{images}[$i]->{height} > $opts{sy}) {
                $cmd = "$scaleProg -scale x$opts{sy} -sharpen 5 \"$tmpFile\" \"$tmpSlideFile\"";
                $dieMsg = "\nCannot scale the slide image!\n";
                system($cmd) == 0 or die $dieMsg;

            # x-scale: scale the slide if it's X width is greater than
            # the value of the sx option and sx != 0
            } elsif ($opts{sx} > 0 and $albumInfo->{images}[$i]->{width} > $opts{sx}) {
                $cmd = "$scaleProg -scale $opts{sx} -sharpen 5 \"$tmpFile\" \"$tmpSlideFile\"";
                $dieMsg = "\nCannot scale the slide image!\n";
                system($cmd) == 0 or die $dieMsg;

            # no-scale: image does not need to be scaled
            } else {
                $dieMsg = "Cannot copy \"$tmpFile\" to \"$tmpSlideFile\"\n";
                copy $tmpFile,$tmpSlideFile or die "$dieMsg $!\n";
            }

            # if we're watermarking the slides, do it now.
            if ($opts{ws}) {
                # check to make sure we have a valid watermark program
                # and that the watermark image exists
                if ($waterMarkProg eq "none") {
                    print "\r\(" . ($i+1) . "/" . ($#{$albumInfo->{images}}+1) ."\) CANNOT Watermark $tmpSlideFile. No Watermark program found! $msgPad";
                } else {
                    print "\r\(" . ($i+1) . "/" . ($#{$albumInfo->{images}}+1) ."\) Watermarking $tmpSlideFile $msgPad";
                    if ($waterMarkProg eq "composite") {
                        $cmd = "$waterMarkProg -compose over -gravity $opts{wg} $opts{wf} \"$tmpSlideFile\" \"$tmpSlideFile\"";
                    } else {
                        # combine reversed the order the image and watermark
                        # were listed on the command line.
                        $cmd = "$waterMarkProg -compose over -gravity $opts{wg} \"$tmpSlideFile\" $opts{wf} \"$tmpSlideFile\"";
                    }
                    $dieMsg = "\nCannot watermark the slide image!\n";
                    system($cmd) == 0 or die $dieMsg;
                }
            }

            # increment the generated count
            $genCnt++;
        } else {
            # increment the skipped count
            print "\r\(" . ($i+1) . "/" . ($#{$albumInfo->{images}}+1) . "\) Skipping $tmpSlideFile $msgPad";
            $skipCnt++;
        }

        # get the image info for the slide
        if ($opts{uo}) {
            # we're using the originals and already have the
            # size, X and Y info of the originals. use those.
            $albumInfo->{images}[$i]->{slidekb} = $albumInfo->{images}[$i]->{size};
            $albumInfo->{images}[$i]->{slidex} = $albumInfo->{images}[$i]->{width};
            $albumInfo->{images}[$i]->{slidey} = $albumInfo->{images}[$i]->{height};
        } else {
            # get the files size and X,Y info for the slide
            my @tmpArr = &getImgInfo($albumInfo->{images}[$i]->{slide});
            $albumInfo->{images}[$i]->{slidekb} = $tmpArr[0];
            $albumInfo->{images}[$i]->{slidex} = $tmpArr[1];
            $albumInfo->{images}[$i]->{slidey} = $tmpArr[2];
        }
    }

    print "\r"; # move back to the start of the line
    print "$genCnt slides generated. $msgPad\n" if $genCnt > 0;
    print "$skipCnt slides skipped because they already existed.\n" if $skipCnt > 0;
    print "Finished generating slide images.\n\n";
}

###########################################################
# genExifInfo - generate the exif info for each jpeg image
#
# generates exif info for all jpg images.
#
# input:
# reference to the options hash
# reference to album info hash
#
# side effects: if the -uec option is set and there is an exif comment in
# the exif header, then the slide description will be overwritten with the
# exif comment. 
#
sub genExifInfo {
    my (%opts) = %{$_[0]};   # options hash
    my ($albumInfo) = $_[1]; # album info
    print "Generating EXIF info\n";

    # generate page for each image
    for my $i (0 .. $#{$albumInfo->{images}}) {
        # get the name of the file
        my $tmpFile = $albumInfo->{images}[$i]->{file};

        # set the exif info for the image
        $albumInfo->{images}[$i]->{exif} = &getExifInfo($tmpFile);

        # set the image description to the exif comment if it exists
        if ($opts{uec}) {
            # check to see if there is a comment field.
            my $haveComment = 0;
	    my $desc = "";
            for my $j (0 .. $#{$albumInfo->{images}[$i]->{exif}}) {
                if ($albumInfo->{images}[$i]->{exif}->[$j]{field} eq "Comment") {
                    if ($haveComment eq 0) {
                        # first line of the comment.
                        $desc = $albumInfo->{images}[$i]->{exif}->[$j]{val};
                        $haveComment++;
                    } else {
                        # there was more than one comment line
                        $desc = $desc . "<br/>" . $albumInfo->{images}[$i]->{exif}->[$j]{val};
                    }
                }
            }
            # if there was comment, save it.
            $albumInfo->{images}[$i]->{desc} = $desc if $haveComment;
        }
    }
}

###########################################################
# getExifInfo - run the exif program, and get the exif info for an image.
#
# This runs the users exif extraction program on an image creating an
# array of hashes. Each array element is a hash which corresponds to each
# line in the output of the exif program.  Each hash has two keys, 'field'
# and 'val'.
#
# jhead - the exif extraction program output in the form:
# exif field : exif value
# the 'field' value corresponds to everything before the first ':'.
# the 'val' value corresponds to everything after the first ':'.
#
# all leading and trailing whitespace is removed from both field and val.
#
# input:  the file we want to get exif info from.
# return: the reference to the array of hashes.
#
sub getExifInfo {
    my ($file) = @_;

    my @exifArr = ();

    # exif info only exists in jpeg files. Return if not.
    return \@exifArr unless ($file =~ /jpe?g/i);

    # get the output of the exif program
    my $cmdOutput = qx/$exifProg "$file"/;

    # split it up into lines and parse each line
    my @cmdArr = split /\n/,$cmdOutput;
    foreach my $line (@cmdArr) {
        # clear out the temporary hash
        my %tmpHash = (field => "", val => "");

        # split on the field delimeters
        my @lineArr = split /:/,$line;

        # add in the field value
        $tmpHash{field} = trimWS($lineArr[0]);
        shift @lineArr; # remove the first element

        # rejoin the line array to preserve any other ':'s in the line
        $line = join ':',@lineArr;
        # add the value to the hash
        $tmpHash{val} = trimWS($line);

        # stuff a reference to the hash at the end of the array
        push @exifArr,\%tmpHash;
    }

    return \@exifArr;
}

###########################################################
# newAlbumInfo - returns a hash structure containing all the
# info about the album.
sub newAlbumInfo {
    return {
        titlebar =>  "My Pictures", # title bar of album
        title =>  "My Pictures", # title of album
        header => "", # header string
        footer => "", # footer string
        images => []  # array of images - created latert
    };
}

###########################################################
# newImgInfo - returns a hash structure containing all the
# info about one file.
sub newImgInfo {
    return {
        file => "",    # string - filename
        desc => "",    # string - description
        width => "",   # images width (in pixels)
        height => "",  # images height (in pixels)
        size => "",    # file size of image in Kb.
        thumb => "",   # filename of thumbnail image
        thumbx => "",  # width of thumbnail image
        thumby => "",  # height of thumbnail image
        slide => "",   # filename of slide image
        slidekb => "", # size in kb of slide the image
        slidex => "",  # width of slide image
        slidey => "",  # height of slide image
        exif => {}     # hash reference - created later
    };
}

###########################################################
# trimWS - from begining and end of input
#
sub trimWS
{
    return "" if (!(defined $_[0]));
    $_[0] =~ s/^\s+|\s+$//go ;
    return $_[0];
}

###########################################################
# printVersion - prints the version info and exists
#
sub printVersion {
    print "\nJason's Image Gallery - jigl\n";
    print "Version $version (c)2002-2003 $author\n";
    print "Please run '$progName -h' for help\n\n";
    exit 0;
}

###########################################################
# printUsage - print the usage and exit
#
sub printUsage {
print <<endOfPrint;
Usage: $progName [options] [directories]
[options]
-cg  --create-gallerydat
                    : Create a gallery.dat file and exit
-uec --use-exif-comment
                    : Use the comment field in the exif header (if it exists)
                      as the slide comment. This will overwrite the description
                      that is written in a gallery.dat file. If used in 
                      conjunction with the -cg option, the comment field will
                      be saved in the gallery.dat file.
                      Default is DISABLED. (can be negated).
-rs  --replace-spaces <a|y|n>
                    : Replaces spaces with underscores "_" in filenames.
                      a - (default) Ask the user if they want to
                      y - replace and do no ask
                      n - do not replace and do no ask
-it --index-title <string>
                    : Sets the title and title-bar of the index.html page
                      to string. This is meant to be used when you are not
                      using a gallery.dat file.
-iw --index-width <1-255>
                    : How many thumbnails per line you want on the index page.
                      Default is 5
-ir --index-row <0-255>
                    : The number of thumbnail rows you want on the index page
                      before a new index page is generated. If 0, there is no
                      limit and only one index page will be generated.
                      Default is 0
-ut  --update-templates
                    : Remove the template files from the local directory and
                      the global default theme directory. This will cause new
                      default template files to be generated in the global
                      default theme directory.
                      Default is DISABLED. (can be negated).
-ft  --force-thumb  : Force thumbnail regeneration (can be negated)
-fs  --force-slide  : Force slide regeneration (can be negated)
-skb --slide-kbsize : Print the file size of the slide on the index page
                      under the thumbnails.
                      Default is ENABLED (can be negated)
-sxy --slide-xysize : Print the slide dimensions under the thumbnails
                      on the index page.
                      Default is ENABLED (can be negated)
-uo --use-original  : Use the original images for the slides - do not
                      generate a scaled slide image.
                      Default is DISABLED. (can be negated)
-lo --link-original : Link to the original images from the slides.
                      Default is DISABLED. (can be negated).
-aro --auto-rotate-originals
                    : Do a lossless rotation of the original images. This
                      option is only useful if your digital camera sets the
                      Orientation field in the EXIF header. All EXIF header
                      information will be kept and the Orientation field
                      will be updated to reflect the rotation.
                      Default is DISABLED. (can be negated).
-gs --generate-slides
                    : Gererate slide pages and link them to the thumbnails.
                      If this option is turned off, slides will not be
                      generated and the info pages will be linked to the
                      thumbnails instead. If neither slide or info pages are
                      generated, the thumbnails will not link to anything.
                      Default is ENABLED. (can be negated).
-gi --generate-info : Gererate info pages and link them to the "info" link
                      on the slide pages. If this option is turned off, info
                      pages will not be generated and the "info" link on the
                      slide pages will dissapear.  If no slides are generated,
                      then the info pages will be linked directly to the 
                      thumbnails.
                      Default is ENABLED. (can be negated).
-sy --slideY <int>  : Scale all slides along the Y-axis to the value given.
                      The X-axis will be scaled to keep the correct proportion.
                      If the height of the original image is greater than
                      this value the slide will be scaled to this value.
                      Otherwise the slide is simply a copy of the original.
                      Default is 480 pixels
-sx --slideX <int>  : Scale all slides along the X-axis to the value given.
                      The Y-axis will be scaled to keep the correct proportion.
                      If the width of the original image is greater than
                      this value the slide will be scaled to this value.
                      Otherwise the slide is simply a copy of the original.
                      Default is 0 pixels
-sle --slide-long-edge
                    : Scale all slides along their longest axis to the value
                      given. The short-axis will be scaled to keep the correct
                      proportion. If the longest axis of the original image
                      is greater than this value the slide will be scaled to
                      this value. Otherwise the slide is simply a copy of
                      the original.
                      Default is 0 pixels
-ty --thumbY <int>  : Scale all thumbnails along the Y-axis to the value given.
                      The X-axis will be scaled to keep the correct proportion.
                      Default is 75 pixels
-tx --thumbX <int>  : Scale all thumbnails along the X-axis to the value given.
                      The Y-axis will be scaled to keep the correct proportion.
                      Default is 0 pixels
-tle --thumb-long-edge
                    : Scale all thumbnails along their longest axis to the
                      value given. The short-axis will be scaled to keep the
                      correct proportion.
                      Default is 0 pixels
-iy --infoY <int>   : Maximum size of the info image in the Y direction. This
                      is simply a scale of the slide image using HTML height
                      and width tags. A new image is not generated.
                      Default is 240 pixels
-ws --watermark-slides
                    : Enable watermarking of the slide images. A watermark
                      file must be present for this option to work.
                      Default is DISABLED. (can be negated).
-wf --watermark-file <filename>
                    : Name of the watermark file to use when -ws is enabled.
                      Default is "watermark.png".
-wg --watermark-gravity <north|south|east|west|northeast|northwest|southeast|
                      southwest>
                    : Where to display the watermark on the slide.
                      Default is southeast.
-gb --go-back       : Prepend a "Go Back" link to the header in the index.html
                      file. If used in conjunction with -cg, the Go Back link
                      will be added to the INDEX-HEADER tag in the newly
                      created gallery.dat file.
                      Default is DISABLED. (can be negated).
-gbs --go-back-string <string>
                    : String to use for the go-back-url link. You could even
                      make this an image to help round out a theme by making
                      this string something like:
                      "<img src=theme/myimage.gif border=0>"
                      Default is "Go Back".
-gburl --go-back-url <url>
                    : URL to use when -gb is enabled. Any URL can be used.
                      Default is '..', the previous directory.
--theme <themeName>
                    : Name of theme to use. Themes files are defined as
                      "themeName.theme". You would just enter the "themeName"
                      portion of the file.
                      Default is "default".
-wd --web-dir <dir> : Directory to put all the gallery files (html, slides,
                      thumbnails and possibly theme files) into. Unless
                      a fully qualified path is used, this directory will be
                      created in the current directory.
                      This option is not used if the -lo or -uo option is set.
                      Default is "web".
-r --recurse        : Recurse through all directories on the command line.
                      This option will omit all directories named "slides",
                      "thumbs", "theme", "web" and the value of -wd if that
                      option is set.
                      This option will ONLY be recognized from the command
                      line to help prevent accidents.
                      Note: Any options listed on the command line when using
                      recursion will be applied to all directories. 
                      Default is DISABLED.
-h --help           : Display this information and exit
-v --version        : Display version and exit
-d --debug <0-5>    : Set debug level. Default is 0
-x --ext .html	    : file extension

Note: If an option listed says it can be negated you can prefix it with "no"
      and the opposite effect will happen. Useful for overriding options
      on the command line that are set elsewhere. e.g. -nouo | --nouse-original
      will NOT use the original files as slides.

[directories]
Default directory is "."

Options can be used in any of three places: (listed ascending precedence)
- All non-comment lines in the \$HOME/.jigl/jigl.opts file in the
  users home directory.
- After the GAL-OPTIONS tag as a single line in the gallery.dat file in
  each of the album directories.
- On the command line.
Regardless of where they are located, they should all be listed in the same
form as you would use them on the command line. Example: -lo -iw 6 -noskb

Theme files can be located in either the directory jigl is processing or in
the .jigl directory in the users home directory.  If no theme is given
then the default/ theme will be used.  If that theme directory does
not exist then one will be created.
(When using an upgraded jigl - this directory should be moved to allow
 new templates and javascript to take effect.)

endOfPrint

exit 0;
}

###########################################################
# removeFiles - remove a list of files, if there is a directory listed it
# will recrusively delete the entire directory as well.
#
sub removeFiles {
    my (@files) = @_;
    foreach my $file (@files) {
        if (-d $file) {
            rmtree("$file",0,0);
        } else {
            # only delete them if they exist.
            my @err = grep {not unlink} $file if -e $file;
            warn "$0: could not delete @err\n" if @err;
        }
    }
}

###########################################################
# genIndexPage - generate the index.html page
#
sub genIndexPage {
    my (%opts)       = %{$_[0]};
    my (%theme)      = %{$_[1]};
    my ($albumInfo)  = $_[2];
    my ($currPage)   = $_[3];
    my ($startIndex) = $_[4];
    my ($endIndex)   = $_[5];

    my $row = 0;  # keep track of what row we're on
    my $col = 0;  # keep track of what image we're on
    my $col1 = 0; # keep track of what imgae we're on for size and dimensions
    my $thumbName = ""; # tmp variable to store thumbnail name
    my $thumbX = "";    # tmp variable to store the thumbnails X dimension
    my $thumbY = "";    # tmp variable to store the thumbnails Y dimension
    my $thumbkb = "";   # tmp variable to store the size (in kb) of the thumb
    my $slideX = "";    # tmp variable to store the slides X dimension
    my $slideY = "";    # tmp variable to store the slides Y dimension
    my $slideKb = "";   # tmp variable to store the size (in kb) of the slide
    my $tmpVar = "";    # tmp variable
    my $line = "";      # variable to store current template line in
    my $themeLine = 0;  # a line was inserted into the template by a theme

    # check to see if there is a local index template present
    if (-e $indexTmpl) {
        print "Using local $indexTmpl\n" if $opts{d};
    } else {
        if ($opts{theme} and (-e $gblIndexTmpl)) {
            print "Using $indexTmpl from theme '$opts{theme}'\n" if $opts{d};
        } elsif (-e $gblIndexTmpl) {
            print "Using global default $indexTmpl\n" if $opts{d};
        } else {
            print "No local or global $indexTmpl file found. Creating default\n";
            &genIndexTemplate;
        }
    }

    # open the index.html file for writing
    my $indexFile;
    if ($currPage == 0) {
        $indexFile = $indexPrefix . $indexExt;
    } else {
        $indexFile = $indexPrefix . $currPage . $indexExt;
    }
    open(INDEX,">$indexFile") or die "Cannot open $indexFile $!\n";

    # try to open the local template file for reading first
    if (-e $indexTmpl) {
        print "Opening $indexTmpl from the local directory'\n" if $opts{d};
        open(INDEXTMPL,"<$indexTmpl") or die "Cannot open $indexTmpl: $!\n";
    } else {
        print "Opening $gblIndexTmpl'\n" if $opts{d};
        open(INDEXTMPL,"<$gblIndexTmpl") or die "Cannot open $gblIndexTmpl: $!\n";
    }

    print "Generating the $indexFile page.\n";

    # read each line of the template file and do what's appropriate
    # for each tag found
    $line = <INDEXTMPL>;
    while ($line) {
        # check each of the keys in the theme file
        foreach my $key (sort {length($b)<=>length($a)} keys %theme) {
            if ($line =~ /$key/) {
                if (defined $theme{$key}) {
                    if ($key eq "INDEX-HEADER" and ($albumInfo->{header} eq "")) {
                        $line =~ s/$key/<br\/>/g;
                        $themeLine = 1;
                    } elsif ($key eq "INDEX-FOOTER" and ($albumInfo->{footer} eq "")) {
                        $line =~ s/$key/<br\/>/g;
                        $themeLine = 1;
                    } else {
                        # standard theme line. Just replace the tag w/value
                        $tmpVar = $theme{$key};
                        $line =~ s/$key/$tmpVar/g;
                        $themeLine = 1;
                    }
                } else {
                    print "WARNING: $key was not defined in the theme file!\n";
                }
            }
        }
        if ($line =~ /INDEX-TITLEBAR/) {
            $line =~ s/INDEX-TITLEBAR/$albumInfo->{titlebar}/g;
        }
        if ($line =~ /INDEX-TITLE/) {
            $line =~ s/INDEX-TITLE/$albumInfo->{title}/g;
        }
        if ($line =~ /TIME-STAMP/) {
            $tmpVar = strftime "%A %d %B %Y %H:%M:%S",localtime(time());
            $line =~ s/TIME-STAMP/$tmpVar/g;
        }
        if ($line =~ /INDEX-HEADER-INFO/) {
            $line =~ s/INDEX-HEADER-INFO/$albumInfo->{header}/g;
        }
        if ($line =~ /INDEX-FOOTER-INFO/) {
            $line =~ s/INDEX-FOOTER-INFO/$albumInfo->{footer}/g;
        }
        if ($line =~ /PICTURES/) {
            # prints out each row of images

            my $row = 0;      # to keep track of what row we're on
            my $donePics = 0; # flag to indicate we're out of pics
            $opts{iw} = 5 if $opts{iw} <= 0; # reset index-width of invalid
            $tmpVar = "";  # clear out the tmp variable

            # generate a new row while we have pictures left
            while (!$donePics) {

                # create table to hold a row of thumbnails & size/dimensions
                $tmpVar = $tmpVar . $theme{"THUMB-ROW"};

                # add the row for the thumbnail images
                if ($tmpVar =~ /IMG-ROW/) {
                    $tmpVar =~ s/IMG-ROW/$theme{"IMG-ROW"}/g;
                }

                # print out the thumbnails up to the value of index-width
                $col = 0; # start at first column
                while ($col < $opts{iw} && !$donePics) {
                    # figure out what image to grab.
                    my $imgIndex = ($opts{iw} * $row) + $col + $startIndex;
                    my $thumbName = $albumInfo->{images}[$imgIndex]->{thumb};
                    # replace any spaces in the name with html friendly code
                    $thumbName =~ s/ /\%20/g;
                    $thumbX  = $albumInfo->{images}[$imgIndex]->{thumbx};
                    $thumbY  = $albumInfo->{images}[$imgIndex]->{thumby};

                    # is this the last of the pictures?
                    $donePics=1 if ($imgIndex == $endIndex);
  
                    # add a thumbnail to the row
                    if ($tmpVar =~ /IMG-COLUMN/) {
                        # remove the link portion of the key if we are not
                        # generating slides or info pages.
                        if (!$opts{gi} and !$opts{gs} and $theme{"IMG-COLUMN"} =~ /<a href=/){
                            $theme{"IMG-COLUMN"} =~ s/<a href="THUMB-LINK">//g;
                            $theme{"IMG-COLUMN"} =~ s/<\/a>//g;
                        }
                        # add the tag to the end so the next img can be added
                        my $tmpCol = $theme{"IMG-COLUMN"} . "\nIMG-COLUMN";
                        $tmpVar =~ s/IMG-COLUMN/$tmpCol/g;
                    }
                    # add the link associated with this thumbnail
                    if ($tmpVar =~ /THUMB-LINK/) {
			my $tmpLink;
                        if ($opts{gs}) {
                            $tmpLink = $imgIndex+1 . $indexExt;
                        } elsif ($opts{gi}) {
                            $tmpLink = $imgIndex+1 . "_info$indexExt";
                        } else {
                            $tmpLink = $thumbName;
                        }
                        $tmpVar =~ s/THUMB-LINK/$tmpLink/g;
                    }
                    # add the image associated with this thumbnail
                    if ($tmpVar =~ /THUMB-FILE/) {
                        $tmpVar =~ s/THUMB-FILE/$thumbName/g;
                    }
                    # add the image width associated with this thumbnail
                    if ($tmpVar =~ /THUMB-WIDTH/) {
                        $tmpVar =~ s/THUMB-WIDTH/$thumbX/g;
                    }
                    # add the image height associated with this thumbnail
                    if ($tmpVar =~ /THUMB-HEIGHT/) {
                        $tmpVar =~ s/THUMB-HEIGHT/$thumbY/g;
                    }

                    $col++; # increment the col count
                }

                # last column in this row. Remove the tag from the line.
                $tmpVar =~ s/IMG-COLUMN//g;

                # print out the sizes and dimensions below the images
                if ($opts{skb} or $opts{sxy}) {

                    # add the row for the thumbnail size and dimensions
                    if ($tmpVar =~ /SIZE-DIMENSION-ROW/) {
                        $tmpVar =~ s/SIZE-DIMENSION-ROW/$theme{"SIZE-DIMENSION-ROW"}/g;
                    }

                    # print out each size/dimension up to the width of
                    # the row that was just generated
                    $col1 = 0;
                    while ($col1 < $col) {
                        my $imgIndex = ($opts{iw} * $row) + $col1;
                        if ($opts{gi} or $opts{gs}) {
                            $slideX = $albumInfo->{images}[$imgIndex]->{slidex};
                            $slideY = $albumInfo->{images}[$imgIndex]->{slidey};
                            $slideKb = $albumInfo->{images}[$imgIndex]->{slidekb};
                        } else {
                            $slideX = $albumInfo->{images}[$imgIndex]->{thumbx};
                            $slideY = $albumInfo->{images}[$imgIndex]->{thumby};
                            $slideKb = $albumInfo->{images}[$imgIndex]->{thumbkb};
                        }

                        # add a thumbnail to the row
                        if ($tmpVar =~ /SIZE-DIMENSION-COLUMN/) {
                            # add tag to the end so the next info can be added
                            my $tmpCol = $theme{"SIZE-DIMENSION-COLUMN"} . "\nSIZE-DIMENSION-COLUMN";
                            $tmpVar =~ s/SIZE-DIMENSION-COLUMN/$tmpCol/g;
                        }

                        # this slides dimensions and size
                        my $tmpDim  = $slideX . "x" . "$slideY";
                        my $tmpSize = "(" . $slideKb . ")";

                        # only print out the fields the user asked us to
                        if ($tmpVar =~ /THUMB-DIMENSIONS/) {
                            if ($opts{sxy}) {
                                $tmpVar =~ s/THUMB-DIMENSIONS/$tmpDim/g;
                            } else {
                                $tmpVar =~ s/THUMB-DIMENSIONS//g;
                            }
                        }
                        if ($tmpVar =~ /THUMB-SIZE/) {
                            if ($opts{skb}) {
                                $tmpVar =~ s/THUMB-SIZE/$tmpSize/g;
                            } else {
                                $tmpVar =~ s/THUMB-SIZE//g;
                            }
                        }
                        $col1++; # increment the column1 count
                    }
                    # last column in this row. Remove the tag from the line.
                    $tmpVar =~ s/SIZE-DIMENSION-COLUMN//g;

                } else {
                    # no size or dimension being printed. remove the tag
                    $tmpVar =~ s/SIZE-DIMENSION-ROW//g;
                }

                $row++; # increment the row count
            }

            $line =~ s/PICTURES/$tmpVar/g;
        }
        if ($line =~ /INDEX-NAVI/) {
            $tmpVar = ""; # clear out the tmp variable
            # only print this if we have more than one page
            if ($albumInfo->{numPages} > 0) {
                for my $i (0 .. $albumInfo->{numPages}) {
		    my $tmpPage;
                    if ($i == 0) {
                        $tmpPage = "./" . $indexPrefix . $indexExt;
                    } else {
                        $tmpPage = "./" . $indexPrefix . $i . $indexExt;
                    }
                    # don't link to the current page we're on
                    if ($i == $currPage) {
                        $tmpVar = $tmpVar . "<$i> ";
                    } else {
                        $tmpVar = $tmpVar . "<a href=\"$tmpPage\" style=text-decoration:none>[" . $i . "]<\/a> ";
                    }
                }
                &trimWS($tmpVar); # remove space from the end of the line
            }
            $line =~ s/INDEX-NAVI/$tmpVar/g;
        }

        # get the next line to process
        if ($themeLine != 0) {
            # we had a theme line, so process this line again.
            $themeLine = 0; # reset so we only process this line once.
        } else {
            # print out the line
            print INDEX $line;

            # get new line
            $line = <INDEXTMPL>;
        }
    }

    close INDEX;     # close the index.html file
    close INDEXTMPL; # close the index_template file

}

###########################################################
# genIndexTemplate - generate the index template
#
sub genIndexTemplate {

    # put the default index template in the global default theme dir.
    open(INDEXTMPL,">$gblIndexTmpl") or die "Cannot open $gblIndexTmpl: $!\n";

print INDEXTMPL <<endoftemplate;
<html>
<!-- Created with jigl - http://xome.net/projects/jigl -->
<!-- -->
<!-- The tag names in this template are used by jigl to insert html code.
     The tags are in all capitals. They can be moved around in the template
     or deleted if desired. To see how this works just compare the template
     file with a generated index.html file. -->
<head>
  <title>INDEX-TITLEBAR</title>
</head>

<!---->
<!-- styles for the title, header and footer fonts -->
<!---->
<style>
    /* title */
    .title {
        font-family: Arial, Helvetica, sans-serif;
        font-size: 20pt;
        color: #dddddd;
        font-weight: normal;
    }
    /* header and footer */
    .hdr_ftr {
        font-family: verdana, sans-serif;
        font-size: 12;
        color: #dddddd;
        font-weight: normal;
    }
</style>

<body bgcolor="#333333" text="#dddddd" link="#95ddff" vlink="#aaaaaa">

<font face="verdana,sans-serif">

<!---->
<!-- title of page -->
<!---->
<table bgcolor="#444444" width=100% border=1 cellspacing=0 cellpadding=3>
    <tr>
        <td class="title">INDEX-TITLE</td>
    </tr>
</table>

INDEX-HEADER

<!---->
<!-- Tables with the index pictures below -->
<!---->
<center>
INDEX-NAVI
PICTURES
</center>

INDEX-FOOTER

<!---->
<!-- general page info below -->
<!---->
<br/>
<table bgcolor="#444444" width=100% border=1 cellspacing=0 cellpadding=3>
    <tr>
        <td><table text="#111111" width=100% border=0 cellspacing=0 cellpadding=3>
            <tr>
                <td align=left class=hdr_ftr>Created on: TIME-STAMP</td>
                <td align=right class=hdr_ftr>Created with <a href="http://xome.net/projects/jigl/">jigl</a></td>
            </tr>
        </table></td>
    </tr>
</table>
</font>
</body>
</html>
endoftemplate

close INDEXTMPL;
}

###########################################################
# genJsFile - generate the Javascript file
#
sub genJsFile {
	my (%opts)	= %{$_[0]};
	my (%theme)	= %{$_[1]};
	my ($albumInfo)	= $_[2];

	# check to see if there is a local javascript file present
	if (-e $jsfile) {
		print "Using local $jsfile\n" if $opts{d};
	} else {
		if ($opts{theme} and (-e $gblJsFile)) {
			print "Using $jsfile from theme '$opts{theme}'\n"
				if $opts{d};
		} elsif (-e $gblJsFile) {
			print "Using global default $jsfile\n" if $opts{d};
		} else {
			print "No local or global $jsfile file found."
				." Creating default\n";
			&genJavaScript;
		}

		print "Generating the javascript file\n";

		copy $gblJsFile,$jsfile
			or die "Cannot copy $gblJsFile to $jsfile $!\n";
	}
}

###########################################################
# genSlidePages - generate the html slide pages
#
sub genSlidePages {
    my (%opts)      = %{$_[0]};
    my (%theme)     = %{$_[1]};
    my ($albumInfo) = $_[2];

    my $slideFile = "";  # file name to create
    my $slideX = "";     # tmp variable to store the slides X dimension
    my $slideY = "";     # tmp variable to store the slides Y dimension
    my $curr0Index = ""; # 0 based index of this image
    my $curr1Index = ""; # 1 based index of this image
    my $prev0Index = ""; # 0 index of previous image
    my $prev1Index = ""; # 1 index of previous image
    my $next0Index = ""; # 0 index of next image
    my $next1Index = ""; # 1 index of next image
    my $tmpVar     = ""; # temp variable
    my $line       = ""; # variable to store current template line in
    my $themeLine  = 0;  # a line was inserted into the template by a theme

    # check to see if there is a local slide template present
    if (-e $slideTmpl) {
        print "Using local $slideTmpl\n" if $opts{d};
    } else {
        if ($opts{theme} and (-e $gblSlideTmpl)) {
            print "Using $slideTmpl from theme '$opts{theme}'\n" if $opts{d};
        } elsif (-e $gblSlideTmpl) {
            print "Using global default $slideTmpl\n" if $opts{d};
        } else {
            print "No local or global $slideTmpl file found. Creating default\n";
            &genSlideTemplate;
        }
    }

    print "Generating the slide html pages\n";

    # create one slide for each image
    for $curr0Index (0 .. $#{$albumInfo->{images}}) {
        # setup all the 0 and 1 based index values
        $curr1Index = $curr0Index + 1;
        $prev0Index = $curr0Index - 1;
        $prev1Index = $curr0Index;
        $next0Index = $curr1Index;
        $next1Index = $curr1Index + 1;

        # handle some special cases
        if ($curr0Index == 0) {
            # this is the first file.
            # the previous index will be the last index
            $prev0Index = $#{$albumInfo->{images}};
            $prev1Index = $#{$albumInfo->{images}} + 1;
        }
        if ($curr0Index == $#{$albumInfo->{images}}) {
            # this is the last file.
            # the next index will be the first index
            $next0Index = 0;
            $next1Index = 1;
        }

        # figure out what files we're supposed to be creating and linking to.
        my $slideFile     = "$curr1Index$indexExt";
        my $infoFile      = $curr1Index ."_info$indexExt";
        my $prevSlideFile = "$prev1Index$indexExt";
        my $nextSlideFile = "$next1Index$indexExt";
        # which index page is this image on.
        my $pgIndex = int($curr0Index / ($opts{iw} * $opts{ir}))
		if $opts{ir} > 0;
	my $indexFile;
        if (($albumInfo->{numPages} == 0) or $pgIndex == 0) {
            $indexFile = $indexPrefix . $indexExt;
        } else {
            $indexFile = $indexPrefix . $pgIndex . $indexExt;
        }

        # open the slide html file for writing
        open(SLIDE,">$slideFile") or die "Cannot open $slideFile $!\n";

        # try to open the local template file for reading
        if (-e $slideTmpl) {
            open(SLIDETMPL,"<$slideTmpl") or die "Cannot open $slideTmpl: $!\n";
        } else {
            open(SLIDETMPL,"<$gblSlideTmpl") or die "Cannot open $gblSlideTmpl: $!\n";
        }

        # read each line of the template file and do what's appropriate
        # for each tag found
        my $line = <SLIDETMPL>;
        while ($line) {
            # check each of the keys in the theme file
            foreach my $key (sort {length($b)<=>length($a)} keys %theme) {
                if ($line =~ /$key/) {
                    if (defined $theme{$key}) {
                        # process any special keys here
                        # don't print the info link if we didn't gen info-pages
                        if ($key eq "INFO-LINK" and !$opts{gi}) {
                            $line =~ s/$key//g;
                            $themeLine = 1;
                        } elsif ($key eq "NEXT-SLIDE-LINK" and $curr1Index == ($#{$albumInfo->{images}} + 1)) {
                            # this is the last slide
                            $line =~ s/$key/LAST-SLIDE-NEXT-LINK/g;
                            $themeLine = 1;
                        } elsif ($key eq "PREV-SLIDE-LINK" and $curr1Index == 1) {
                            # this is the first slide
                            $line =~ s/$key/FIRST-SLIDE-PREV-LINK/g;
                            $themeLine = 1;
                        } else {
                            # nothing special about this key
                            $tmpVar = $theme{$key};
                            $line =~ s/$key/$tmpVar/g;
                            $themeLine = 1;
                        }
                    } else {
                        print "WARNING: $key was not defined in the theme file!\n";
                    }
                }
            }
            if ($line =~ /ORIG-IMAGE-NAME/) {
                $line =~ s/ORIG-IMAGE-NAME/$albumInfo->{images}[$curr0Index]->{file}/g;

            }
            if ($line =~ /NEXT-SLIDE-NAME/) {
                $tmpVar = $albumInfo->{images}[$next0Index]->{slide};
                $tmpVar =~ s/ /\%20/g;
                $line =~ s/NEXT-SLIDE-NAME/$tmpVar/g;

            }
            if ($line =~ /PREV-SLIDE-HTML/) {
                $line =~ s/PREV-SLIDE-HTML/$prevSlideFile/g;

            }
            if ($line =~ /INDEX-HTML/) {
                $line =~ s/INDEX-HTML/$indexFile/g;

            }
            if ($line =~ /INFO-HTML/) {
                $line =~ s/INFO-HTML/$infoFile/g;

            }
            if ($line =~ /NEXT-SLIDE-HTML/) {
                $line =~ s/NEXT-SLIDE-HTML/$nextSlideFile/g;

            }
            if ($line =~ /SLIDE-IMAGE/) {
                # get some info about the slide
                my $origImg  = $albumInfo->{images}[$curr0Index]->{file};
                $origImg  =~ s/ /\%20/g; # make any spaces web friendly
                my $slideImg = $albumInfo->{images}[$curr0Index]->{slide};
                $slideImg =~ s/ /\%20/g; # make any spaces web friendly
                my $slideX   = $albumInfo->{images}[$curr0Index]->{slidex};
                my $slideY   = $albumInfo->{images}[$curr0Index]->{slidey};

                # check to see if we need to link the slide to the original
                if ($opts{lo}) {
                    $tmpVar = "<a href=\"$origImg\"><img src=\"$slideImg\" width=\"$slideX\" height=\"$slideY\" border=\"1\" onload='resizeJglPix(this)'/></a>";
                } else {
                    $tmpVar = "<img src=\"$slideImg\" width=\"$slideX\" height=\"$slideY\" border=\"1\" onload='resizeJglPix(this)'/>";

                }
                $line =~ s/SLIDE-IMAGE/$tmpVar/g;

            }
            if ($line =~ /SLIDE-DESCRIPTION/) {
                $line =~ s/SLIDE-DESCRIPTION/$albumInfo->{images}[$curr0Index]->{desc}/g;

            }
            if ($line =~ /SLIDE-COUNT/) {
                $tmpVar = "\(" . $curr1Index . "\/" . ($#{$albumInfo->{images}} + 1) . "\)";
                $line =~ s/SLIDE-COUNT/$tmpVar/g;
            }
	    if ($line =~ /INDEX-TITLE/) {
		$line =~ s/INDEX-TITLE/$albumInfo->{title}/g;
	    }

            # get the next line to process
            if ($themeLine != 0) {
                # we had a theme line, so process this line again.
                $themeLine = 0; # reset so we only process this line once.
            } else {
                # print out the line
                print SLIDE $line;

                # get new line
                $line = <SLIDETMPL>;
            }
        }

        close SLIDE;   # close the index.html file
        close SLIDETMPL; # close the index_template file
    }
}

###########################################################
# genJavaScript
#
sub genJavaScript {

    # put the default slide template in the default theme dir.
    open(JSFILE,">$gblJsFile") or die "Cannot open $gblJsFile: $!\n";

print JSFILE <<endoftemplate;
<!---------------------------------------------------------------->
function resizeJglPix(pix){
	var ww = 0;
	var wh = 0;
	var rat = 1.0;

	getWindowSize();
	// leave 5% for garnish
	ww = .95 * window.jglWidth;
	wh = .95 * window.jglHeight;

	if (pix.width <= ww && pix.height <= wh) {
		return;		// do nothing - smaller than window
	} else if (pix.width >  ww && pix.height <= wh) {
		rat = ww/pix.width;
	} else if (pix.width <= ww && pix.height >  wh) {
		rat = wh/pix.height;
	} else if (pix.width >  ww && pix.height >  wh) {
		rat = Math.min(ww/pix.width,wh/pix.height);
	}
	pix.width=pix.width * rat;
	pix.height=pix.height * rat;
}
function getWindowSize(){
	var ww = 0;
	var wh = 0;
	d = document;
	if ( typeof window.innerWidth != 'undefined' )
		ww = window.innerWidth;  // NN and Opera version
	else {
		if ( d.documentElement
		&& typeof d.documentElement.clientWidth!='undefined'
		&& d.documentElement.clientWidth != 0 )
			ww = d.documentElement.clientWidth;
		else if ( d.body && typeof d.body.clientWidth != 'undefined' )
			ww = d.body.clientWidth;
	}
	window.jglWidth = ww;
	if ( typeof window.innerHeight != 'undefined' )
		wh = window.innerHeight;  // NN and Opera version
	else {
		if ( d.documentElement
		&& typeof d.documentElement.clientHeight!='undefined'
		&& d.documentElement.clientHeight != 0 )
			wh = d.documentElement.clientHeight;
		else if ( d.body && typeof d.body.clientHeight != 'undefined' )
			wh = d.body.clientHeight;
	}
	window.jglHeight = wh;
}
<!---------------------------------------------------------------->
endoftemplate

    close JSFILE;
}

###########################################################
# genSlideTemplate - generate the template for each slide page
#
sub genSlideTemplate {

    # put the default slide template in the default theme dir.
    open(SLIDETMPL,">$gblSlideTmpl") or die "Cannot open $gblSlideTmpl: $!\n";

print SLIDETMPL <<endoftemplate;
<html>
<!-- Created with jigl - http://xome.net/projects/jigl -->
<!-- -->
<!-- The tag names in this template are used by jigl to insert html code.
     The tags are in all capitals. They can be moved around in the template
     or deleted if desired. To see how this works just compare the template
     file with a generated slide. -->
<head>
   <title>Image: ORIG-IMAGE-NAME SLIDE-COUNT</title>
   <script language="JavaScript" src="jigl.js"></script>
   <!---->
   <!-- Preload the next image here -->
   <!---->
   <script language="javascript">       <!--
       if (document.images)    {
	  Image1          = new Image();
	  Image1.src      = "NEXT-SLIDE-NAME";
       }       //-->
   </script>
</head>

<body bgcolor="#333333" text="#dddddd" link="#95ddff" vlink="#aaaaaa" onload='getWindowSize()'>

<font face="verdana,sans-serif">
<!---->
<!-- Top Navigation -->
<!---->
<table border="4" cellspacing="2" cellpadding="4" class="nonprint" style="border-style:outset; z-index:1; position:fixed; top:10px; left:10px;">
    <tr>
	<td align="center">PREV-SLIDE-LINK</td>
	<td align="center">INDEX-LINK</td>
	<td align="center">INFO-LINK</td>
	<td align="center">NEXT-SLIDE-LINK</td>
    </tr>
</table>

<center>
<table cellspacing="5" cellpadding="4">
    <tr>
	<!---->
	<!-- Image -->
	<!---->
	<td bgcolor="#ffffff" align="center" valign="middle">
	    SLIDE-IMAGE
	</td>
    </tr>
    <!---->
    <!-- Comment -->
    <!---->
    <tr><td align="center">
	<table width="60%" bgcolor="#444444" border="1" cellspacing="0" cellpadding="0" style="z-index=1; position:relative; top:-5em;">
	    <tr><td align=center>SLIDE-DESCRIPTION<br/>SLIDE-COUNT</td></tr>
	</table>
    </td></tr>
</table>

</font>
</center>
</body>
</html>
endoftemplate

    close SLIDETMPL;
}

###########################################################
# genInfoPages - generate the html EXIF pages
#
sub genInfoPages {
    my (%opts) = %{$_[0]};
    my (%theme) = %{$_[1]};
    my ($albumInfo) = $_[2];

    my $infoFile      = ""; # file name of info page to create
    my $slideFile     = ""; # slide file associated with current info page
    my $prevSlideFile = ""; # next slide page
    my $prevInfoFile  = ""; # next info page
    my $nextSlideFile = ""; # previous slide page
    my $nextInfoFile  = ""; # previous info page
    my $slideX = "";     # tmp variable to store the slides X dimension
    my $slideY = "";     # tmp variable to store the slides Y dimension
    my $curr0Index = ""; # 0 based index of this image
    my $curr1Index = ""; # 1 based index of this image
    my $prev0Index = ""; # 0 index of previous image
    my $prev1Index = ""; # 1 index of previous image
    my $next0Index = ""; # 0 index of next image
    my $next1Index = ""; # 1 index of next image
    my $tmpVar     = ""; # temp variable
    my $line       = ""; # variable to store current template line in
    my $themeLine  = 0;  # a line was inserted into the template by a theme

    # check to see if there is a local info template present
    if (-e $infoTmpl) {
        print "Using local $infoTmpl\n" if $opts{d};
    } else {
        if ($opts{theme} and (-e $gblInfoTmpl)) {
            print "Using $infoTmpl from theme '$opts{theme}'\n" if $opts{d};
        } elsif (-e $gblInfoTmpl) {
            print "Using global default $infoTmpl\n" if $opts{d};
        } else {
            print "No local or global $infoTmpl file found. Creating default\n";
            &genInfoTemplate;
        }
    }

    print "Generating the info html pages\n";

    # create one info page for each image
    for my $curr0Index (0 .. $#{$albumInfo->{images}}) {
        # setup all the 0 and 1 based index values
        my $curr1Index = $curr0Index + 1;
        my $prev0Index = $curr0Index - 1;
        my $prev1Index = $curr0Index;
        my $next0Index = $curr1Index;
        my $next1Index = $curr1Index + 1;

        # handle some special cases
        if ($curr0Index == 0) {
            # this is the first file.
            # the previous index will be the last index
            $prev0Index = $#{$albumInfo->{images}};
            $prev1Index = $#{$albumInfo->{images}} + 1;
        }
        if ($curr0Index == $#{$albumInfo->{images}}) {
            # this is the last file.
            # the next index will be the first index
            $next0Index = 0;
            $next1Index = 1;
        }

        # figure out what files we're supposed to be creating and linking to.
        my $infoFile      =  $curr1Index ."_info$indexExt";
        my $slideFile     = "$curr1Index$indexExt";
        my $prevSlideFile = "$prev1Index$indexExt";
        my $prevInfoFile  =  $prev1Index ."_info$indexExt";
        my $nextSlideFile = "$next1Index$indexExt";
        my $nextInfoFile  =  $next1Index ."_info$indexExt";
        # which index page is this image on.
        my $pgIndex = int($curr0Index / ($opts{iw} * $opts{ir}))
		if $opts{ir} > 0;
	my $indexFile;
        if (($albumInfo->{numPages} == 0) or $pgIndex == 0) {
            $indexFile = $indexPrefix . $indexExt;
        } else {
            $indexFile = $indexPrefix . $pgIndex . $indexExt;
        }

        # open the info html file for writing
        open(INFO,">$infoFile") or die "Cannot open $infoFile $!\n";

        # try and open the local template file for reading
        if (-e $infoTmpl) {
            open(INFOTMPL,"<$infoTmpl") or die "Cannot open $infoTmpl: $!\n";
        } else {
            open(INFOTMPL,"<$gblInfoTmpl") or die "Cannot open $gblInfoTmpl: $!\n";
        }

        # read each line of the template file and do what's appropriate
        # for each tag found
        my $line = <INFOTMPL>;
        while ($line) {
            # check each of the keys in the theme file
            foreach my $key (sort {length($b)<=>length($a)} keys %theme) {
                if ($line =~ /$key/) {
                    if (defined $theme{$key}) {
                        # process any special keys here
                        # don't print slide links if we didn't gen slide-pages
                        if ($key eq "PREV-SLIDE-LINK" and !$opts{gs}) {
                            $line =~ s/$key//g;
                            $themeLine = 1;
                        } elsif ($key eq "NEXT-SLIDE-LINK" and !$opts{gs}) {
                            $line =~ s/$key//g;
                            $themeLine = 1;
                        } elsif ($key eq "THIS-SLIDE-LINK" and !$opts{gs}) {
                            $line =~ s/$key//g;
                            $themeLine = 1;
                        } elsif ($key eq "NEXT-INFO-LINK" and $curr1Index == ($#{$albumInfo->{images}} + 1)) {
                            # this is the last info page
                            $line =~ s/$key/LAST-INFO-NEXT-LINK/g;
                            $themeLine = 1;
                        } elsif ($key eq "NEXT-SLIDE-LINK" and $curr1Index == ($#{$albumInfo->{images}} + 1)) {
                            # this is the last slide
                            $line =~ s/$key/LAST-SLIDE-NEXT-LINK/g;
                            $themeLine = 1;
                        } elsif ($key eq "PREV-INFO-LINK" and $curr1Index == 1) {
                            # this is the first info page
                            $line =~ s/$key/FIRST-INFO-PREV-LINK/g;
                            $themeLine = 1;
                        } elsif ($key eq "PREV-SLIDE-LINK" and $curr1Index == 1) {
                            # this is the first slide
                            $line =~ s/$key/FIRST-SLIDE-PREV-LINK/g;
                            $themeLine = 1;
                        } else {
                            # nothing special about this key
                            $tmpVar = $theme{$key};
                            $line =~ s/$key/$tmpVar/g;
                            $themeLine = 1;
                        }
                    } else {
                        print "WARNING: $key was not defined in the theme file!\n";
                    }
                }
            }
            if ($line =~ /ORIG-IMAGE-NAME/) {
                $line =~ s/ORIG-IMAGE-NAME/$albumInfo->{images}[$curr0Index]->{file}/g;

            }
            if ($line =~ /NEXT-SLIDE-NAME/) {
                $tmpVar = $albumInfo->{images}[$next0Index]->{slide};
                $tmpVar =~ s/ /\%20/g;
                $line =~ s/NEXT-SLIDE-NAME/$tmpVar/g;

            }
            if ($line =~ /THIS-SLIDE-HTML/) {
                $line =~ s/THIS-SLIDE-HTML/$slideFile/g;

            }
            if ($line =~ /PREV-SLIDE-HTML/) {
                $line =~ s/PREV-SLIDE-HTML/$prevSlideFile/g;

            }
            if ($line =~ /PREV-INFO-HTML/) {
                $line =~ s/PREV-INFO-HTML/$prevInfoFile/g;

            }
            if ($line =~ /INDEX-HTML/) {
                $line =~ s/INDEX-HTML/$indexFile/g;

            }
            if ($line =~ /NEXT-INFO-HTML/) {
                $line =~ s/NEXT-INFO-HTML/$nextInfoFile/g;

            }
            if ($line =~ /NEXT-SLIDE-HTML/) {
                $line =~ s/NEXT-SLIDE-HTML/$nextSlideFile/g;

            }
            if ($line =~ /INFO-IMAGE/) {
                # get the slide dimensions
                my $slideX = $albumInfo->{images}[$curr0Index]->{slidex};
                my $slideY = $albumInfo->{images}[$curr0Index]->{slidey};

                # set the Y dimension of the slide image to the value of
                # the -iy option and scale the X value to maintain the aspect
                # ratio. If slides height is smaller than the value of
                # the -iy option, don't do anything.
                if ($slideY > $opts{iy}) {
                    my $scaleVal = ($slideY/$opts{iy});
                    # this rounds the division to the nearest integer
                    $slideX = sprintf("%.0f",($slideX / $scaleVal));
                    $slideY = $opts{iy};
                }

                # get some other info about the slide and image
                my $origImg  = $albumInfo->{images}[$curr0Index]->{file};
                $origImg  =~ s/ /\%20/g; # make any spaces web friendly
                my $slideImg = $albumInfo->{images}[$curr0Index]->{slide};
                $slideImg =~ s/ /\%20/g; # make any spaces web friendly


                # check to see if we need to link the slide to the original
                if ($opts{lo}) {
                    $tmpVar = "<a href=\"$origImg\"><img src=\"$slideImg\" width=\"$slideX\" height=\"$slideY\" border=\"0\"/></a>";
                } else {
                    $tmpVar = "<img src=\"$slideImg\" width=\"$slideX\" height=\"$slideY\" border=\"0\"/>";

                }
                $line =~ s/INFO-IMAGE/$tmpVar/g;

            }
            if ($line =~ /SLIDE-DESCRIPTION/) {
                $line =~ s/SLIDE-DESCRIPTION/$albumInfo->{images}[$curr0Index]->{desc}/g;

            }
            if ($line =~ /SLIDE-COUNT/) {
                $tmpVar = "\(" . $curr1Index . "\/" . ($#{$albumInfo->{images}} + 1) . "\)";
                $line =~ s/SLIDE-COUNT/$tmpVar/g;

            }
            if ($line =~ /EXIF-NAME-COL/) {
                # returns all the exif names available for this image.
                # each name (i.e. date, apature, shutter speed, flash...),
                # will have a <nobr>before it, and a <br/> after it.
                # this is really meant to be put in a <td></td> column
             
                # do we have exifInfo to print
                if ($#{$albumInfo->{images}[$curr0Index]->{exif}} > 0) {
                    $tmpVar = ""; # clear out the var

                    # create the exif name column
                    for my $j (0 .. $#{$albumInfo->{images}[$curr0Index]->{exif}}) {
                       $tmpVar = $tmpVar . "<nobr/>$albumInfo->{images}[$curr0Index]->{exif}->[$j]{field}<br/>\n";
                    }
                } else {
                    $tmpVar = "<nobr/>No EXIF info available<br/>\n";
                }
                $line =~ s/EXIF-NAME-COL/$tmpVar/g;
            }
            if ($line =~ /EXIF-VAL-COL/) {
                # returns all the exif values available for this image.
                # each value (corresponding to the names above)
                # will have a <nobr/>before it, and a <br/> after it.
                # this is really meant to be put in a <td></td> column
             
                # do we have exifInfo to print
                if ($#{$albumInfo->{images}[$curr0Index]->{exif}} > 0) {
                    $tmpVar = ""; # clear out the var

                    # create the exif value column
                    for my $j (0 .. $#{$albumInfo->{images}[$curr0Index]->{exif}}) {
                       $tmpVar = $tmpVar . "<nobr/>&nbsp;:&nbsp;$albumInfo->{images}[$curr0Index]->{exif}->[$j]{val}<br/>\n";
                    }
                } else {
                    $tmpVar = "&nbsp;\n";
                }
                $line =~ s/EXIF-VAL-COL/$tmpVar/g;
            }
	    if ($line =~ /INDEX-TITLE/) {
		$line =~ s/INDEX-TITLE/$albumInfo->{title}/g;
	    }

            # get the next line to process
            if ($themeLine != 0) {
                # we had a theme line, so process this line again.
                $themeLine = 0; # reset so we only process this line once.
            } else {
                # print out the line
                print INFO $line;

                # get new line
                $line = <INFOTMPL>;
            }
        }

        close INFO;   # close the index.html file
        close INFOTMPL; # close the index_template file
    }
}

###########################################################
# genInfoTemplate - generate the template for each info page
#
sub genInfoTemplate {

    # put the default into template in the default theme dir.
    open(INFOTMPL,">$gblInfoTmpl") or die "Cannot open $gblInfoTmpl: $!\n";

print INFOTMPL <<endoftemplate;
<html>
<!-- Created with jigl - http://xome.net/projects/jigl -->
<!-- -->
<!-- The tag names in this template are used by jigl to insert html code.
     The tags are in all capitals. They can be moved around in the template
     or deleted if desired. To see how this works just compare the template
     file with a generated info page. -->
<head>
   <title>Info for image: ORIG-IMAGE-NAME SLIDE-COUNT</title>
   <!---->
   <!-- Preload the next image here -->
   <!---->
   <script language="javascript">       <!--
       if (document.images)    {
          Image1          = new Image();
          Image1.src      = "NEXT-SLIDE-NAME";
       }       //-->
   </script>
</head>

<body bgcolor="#333333" text="#dddddd" link="#95ddff" vlink="#aaaaaa">

<font face="verdana,sans-serif">
<center>

<!---->
<!-- Top Navigation -->
<!---->
<table width=60% border=0 cellspacing=0 cellpadding=2>
    <tr>
        <td align=left>PREV-SLIDE-LINK</td>
        <td align=left>PREV-INFO-LINK</td>
        <td>&nbsp;</td>
        <td align=right>NEXT-INFO-LINK</td>
        <td align=right>NEXT-SLIDE-LINK</td>
    </tr>
    <tr>
        <td colspan=5 align=center>INDEX-LINK &nbsp; THIS-SLIDE-LINK</td>
    </tr>
</table>

<!---->
<!-- Image/exif info -->
<!---->
<table border=0 cellspacing=0 cellpadding=4>
    <tr><td>&nbsp;</td></tr>
    <tr>
        <!---->
        <!-- Image -->
        <!---->
        <td align=center valign=center>
            <table cellspacing=0 cellpadding=2>
                <tr><td bgcolor="#ffffff" align=center valign=middle>
                    INFO-IMAGE
                </td></tr>
            </table>
        </td>
        <!---->
        <!-- EXIF Info -->
        <!---->
        <td align=left valign=top>
            <table bgcolor="#444466" cellspacing=0 cellpadding=5 border=1>
                <tr>
                    <td>
                        <table border=0 cellspacing=0 cellpadding=0>
                            <tr>
                                <td>
EXIF-NAME-COL
                                </td>
                                <td>
EXIF-VAL-COL
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>
            </table>
        </td>
        <td>&nbsp;</td>
    </tr>
</table>
<!---->
<!-- Bottom Navigation -->
<!---->
<table width=60% border=0 cellspacing=0 cellpadding=2>
    <!---->
    <!-- Comment -->
    <!---->
    <tr><td>&nbsp;</td></tr>
    <tr>
        <td colspan=5>
            <table width=100% bgcolor="#444444" border=1 cellspacing=0 cellpadding=0>
                <tr><td align=center>SLIDE-DESCRIPTION<br/>SLIDE-COUNT</td></tr>
            </table>
        </td>
    </tr>
    <tr><td>&nbsp;</td></tr>
    <tr>
        <td colspan=5 align=center>INDEX-LINK &nbsp; THIS-SLIDE-LINK</td>
    </tr>
    <tr>
        <td align=left>PREV-SLIDE-LINK</td>
        <td align=left>PREV-INFO-LINK</td>
        <td>&nbsp;</td>
        <td align=right>NEXT-INFO-LINK</td>
        <td align=right>NEXT-SLIDE-LINK</td>
    </tr>
</table>

</font>
</center>
</body>
</html>

endoftemplate

    close INFOTMPL;
}

###########################################################
# readTheme - read in the theme.
#
# We check to make sure the theme file exists in the checkOpts() func.
# We can assume that the theme file exists in the global dir. If not, we
# are creating a default theme.
#
# returns a hash where the key is the tag and the value is the html code to
# insert.
#
sub readTheme {
    my (%opts) = %{$_[0]};

    my %thash = ();  # empty theme hash
    my $themeFile = $opts{theme} . ".theme";
    my $gblThemeFile = $gblThemeDir . "/" . $opts{theme} . "/" . $themeFile;

    # Check to see if the theme file exists.
    if (-e $gblThemeFile) {
        $themeFile = $gblThemeFile;
    } else {
        if ($opts{theme} ne "default") {
            print "Error: $opts{theme} does not exist. Using default theme instead!\n";
            $opts{theme} = "default";
        }

        # we couldn't find the theme specified. Create the default
        # theme and use that.
        $themeFile = $gblThemeFile;
        print "Default theme did not exist. Creating.\n";

        my $dieMsg = "Cannot create the directory '$jiglRCDir'.\n";
        mkdir $jiglRCDir,0755 or die "$dieMsg : $!\n" if (!-d $jiglRCDir);

        $dieMsg = "Cannot create the directory '$gblThemeDir'.\n";
        mkdir $gblThemeDir,0755 or die "$dieMsg : $!\n" if (!-d $gblThemeDir);

        my $defaultDir = $gblThemeDir . "/default";
        $dieMsg = "Cannot create the directory '$defaultDir'.\n";
        mkdir $defaultDir,0755 or die "$dieMsg : $!\n" if (!-d $defaultDir);

        &genDefaultTheme($themeFile);
    }

    # read in the theme file.
    open(THEME,"<$themeFile") or die "Cannot open '$themeFile': $!\n";

    # make a hash of all the theme tags and their values
    my $currTag = ""; # key into the hash
    my $tagVal  = ""; # value of the hash
    while (<THEME>) {
        chop $_;
        if ($_ =~ /^#/) {
            # skip - line is a comment
        } elsif ($_ =~ /^[ ]*$/) {
            # skip - line is blank
        } elsif ($_ =~ m/^<([A-Z\-_]+)>/) {
            # start of a tag definition
            $currTag = $1;
            $thash{$currTag} = "";
        } elsif ($_ =~ /^<\/$currTag>/) {
            # end of a tag definition
            chop($thash{$currTag}); # remove the last newline of this tag.
            $currTag = "";          # reset the tag
            $tagVal = "";           # reset the value
        } elsif ($currTag ne "") {
            # we're inside a tag. Add this line to the currTag hash
            # put newline at end to preserve the html structure when viewing source
            $thash{$currTag} = $thash{$currTag} . $_ . "\n";
        } else {
            # dunno what this line is
            print "Error in Theme: Cannot process this line: '$_'\n";
        }
    }

    close THEME;

    if ($opts{d} == 5) {
        for my $key (keys %thash) {
            print "$key : $thash{$key}\n";
        }
    }
    return %thash;
}

###########################################################
# genDefaultTheme - Generate the default theme for jigl.
# The default.theme file will be written in the current directory.
#
sub genDefaultTheme {
    my ($theme) = @_;

    open(THEME,">$theme") or die "Cannot open $theme: $!\n";

print THEME <<endoftheme;
# default theme for jigl

# Link to index.html
<INDEX-LINK>
<a href="INDEX-HTML">Index</a>
</INDEX-LINK>

# Link to a slides info page
<INFO-LINK>
<a href="INFO-HTML">Info</a>
</INFO-LINK>

# Link to the current slide. Used on info page
<THIS-SLIDE-LINK>
<a href="THIS-SLIDE-HTML">This Slide</a>
</THIS-SLIDE-LINK>

# Link to next slide
<NEXT-SLIDE-LINK>
<a href="NEXT-SLIDE-HTML">Next &gt;&gt;</a>
</NEXT-SLIDE-LINK>

# The Next Link to use on the last slide page
<LAST-SLIDE-NEXT-LINK>
Last Slide
</LAST-SLIDE-NEXT-LINK>

# Link to previous slide
<PREV-SLIDE-LINK>
<a href="PREV-SLIDE-HTML">&lt;&lt; Prev</a>
</PREV-SLIDE-LINK>

# The Prev Link to use on the first slide page
<FIRST-SLIDE-PREV-LINK>
First Slide
</FIRST-SLIDE-PREV-LINK>

# Link to next info page
<NEXT-INFO-LINK>
<a href="NEXT-INFO-HTML">Next Info &gt;&gt;</a>
</NEXT-INFO-LINK>

# The Next Link to use on the last info page
<LAST-INFO-NEXT-LINK>
Last Info
</LAST-INFO-NEXT-LINK>

# Link to previous info page
<PREV-INFO-LINK>
<a href="PREV-INFO-HTML">&lt;&lt; Prev Info</a>
</PREV-INFO-LINK>

# The Prev Link to use on the first info page
<FIRST-INFO-PREV-LINK>
First Info
</FIRST-INFO-PREV-LINK>

# Header area on index page
<INDEX-HEADER>
<!---->
<!-- Header info below -->
<!---->
<p>
<table bgcolor="#444466" border=1 cellspacing=0 cellpadding=6>
    <tr>
        <td class="hdr_ftr">
            INDEX-HEADER-INFO
        </td>
    </tr>
</table>
</p>
</INDEX-HEADER>

# Footer area on index page
<INDEX-FOOTER>
<!---->
<!-- Footer info below -->
<!---->
<p>
<table bgcolor="#444466" border=1 cellspacing=0 cellpadding=6>
    <tr>
        <td class="hdr_ftr">
            INDEX-FOOTER-INFO
        </td>
    </tr>
</table>
</p>
</INDEX-FOOTER>

# Table around each row of thumbnails
# This tag must be present and must contain the two tags:
# IMG-ROW and SIZE-DIMENSION-ROW
#
<THUMB-ROW>
<p>
<!--thumb-row-->
<table bgcolor="#444444" border=1 cellspacing=0 cellpadding=3>
    <tr>
        <td><table bgcolor="#444444" border=0 cellspacing=0 cellpadding=4>
IMG-ROW
SIZE-DIMENSION-ROW
        </table></td>
    </tr>
</table>
</p>
</THUMB-ROW>

# Row of the actual thumbnails
# This tag must be present and must contain the IMG-COLUMN tag
#
<IMG-ROW>
            <tr>
IMG-COLUMN
            </tr>
</IMG-ROW>

# Row of size and dimension information under each slide
# This tag must be present and must contain the SIZE-DIMENSION-COLUMN tag.
#
<SIZE-DIMENSION-ROW>
            <tr>
SIZE-DIMENSION-COLUMN
            </tr>
</SIZE-DIMENSION-ROW>

# An individual thumbnail
# This tag must be present.
#
<IMG-COLUMN>
                <td valign="middle" align="center">
                    <a href="THUMB-LINK"><img src="THUMB-FILE" width="THUMB-WIDTH" height="THUMB-HEIGHT" border="0"/></a></td>
</IMG-COLUMN>

# The size and dimension information for an individual thumbnail
# This tag must be present.
#
<SIZE-DIMENSION-COLUMN>
                <td valign=middle align=center>THUMB-DIMENSIONS THUMB-SIZE</td>
</SIZE-DIMENSION-COLUMN>
endoftheme

    close THEME;
}
