use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Shell::POSIX::Select',
    'VERSION_FROM'	=> 'Select.pm', # finds $VERSION
    'PREREQ_PM'		=> { 
					File::Spec::Functions => 0 ,
					Filter::Simple => 0 ,
			    Text::Balanced => 1.89 ,
			    Carp => 0 
			    }, # e.g., Module::Name => 1.1
#		'PL_FILES' => {
#			'PLX_maker' => [ qw ( pick.plx delete_files.plx ) ]
#		},
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'Select.pm', # retrieve abstract from module
       AUTHOR     => 'Tim Maher <tim@teachmeperl.com>') : () ),
);
