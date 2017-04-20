#!/bin/bash
#
#TODO:  output api
#
# Walkthrough:
# - get a list of srpm package names that are included in BRT
# - loop until ".end" got entered:
#   - read newpackage from stdin
#   - check if newpackage is in brtsrpms list > next loop
#   - check if newpackage is in module rpm list > next loop
#   - get build deps from newpackage
#   - loop over build deps:
#     - check if build dep is in brtsrpms list > next loop
#     - check if build dep is in module rpm list > next loop
#     - otherwise add build dep to module rpm list
#       and output modulemd snipped with rpm name and rationale


## #get a list of build deps from a certain binary rpm:
## repoquery --disablerepo=Dropbox --releasever 26 --requires --recursive --resolve  --qf "%{SOURCERPM}" vim-minimal | sort -n | uniq

binaryrpm=""
modulerpms=()
modulerpmsfile=`mktemp modulerpms.XXX`
moduleapifile=`mktemp moduleapi.XXX`
moduleprofilefile=`mktemp moduleprofile.XXX`
alreadyprocessed=`mktemp moduledepprocessed.XXX`
brtrepo="https://kojipkgs.stg.fedoraproject.org/compose/branched/jkaluza/latest-Boltron-26/compose/base-runtime/x86_64/os/"

solvedbuilddeps=("hostname" "multilib-rpm-config" "help2man" "autoconf" "automake" "golang" "perl" "perl-Algorithm-Diff" "perl-Archive-Tar" \
            "perl-Archive-Zip" "perl-autodie" "perl-B-Debug" "perl-bignum" "perl-Carp" "perl-Compress-Bzip2" "perl-Compress-Raw-Bzip2" \
            "perl-Compress-Raw-Zlib" "perl-Config-Perl-V" "perl-constant" "perl-CPAN" "perl-CPAN-Meta" "perl-CPAN-Meta-Requirements" \
            "perl-CPAN-Meta-YAML" "perl-Data-Dumper" "perl-Data-OptList" "perl-Data-Section" "perl-DB_File" "perl-Devel-PPPort" \
            "perl-Devel-Size" "perl-Digest" "perl-Digest-MD5" "perl-Digest-SHA" "perl-Encode" "perl-Env" "perl-experimental" "perl-Exporter" \
            "perl-ExtUtils-CBuilder" "perl-ExtUtils-Install" "perl-ExtUtils-MakeMaker" "perl-ExtUtils-Manifest" "perl-ExtUtils-ParseXS" \
            "perl-Fedora-VSP" "perl-File-Fetch" "perl-File-HomeDir" "perl-File-Path" "perl-File-Temp" "perl-File-Which" "perl-Filter" \
            "perl-Filter-Simple" "perl-generators" "perl-Getopt-Long" "perl-HTTP-Tiny" "perl-inc-latest" "perl-IO-Compress" \
            "perl-IO-Socket-IP" "perl-IPC-Cmd" "perl-IPC-System-Simple" "perl-IPC-SysV" "perl-JSON-PP" "perl-libnet" "perl-local-lib" \
            "perl-Locale-Codes" "perl-Locale-Maketext" "perl-Math-BigInt" "perl-Math-BigInt-FastCalc" "perl-Math-BigRat" "perl-MIME-Base64" \
            "perl-Module-Build" "perl-Module-CoreList" "perl-Module-Load" "perl-Module-Load-Conditional" "perl-Module-Metadata" \
            "perl-MRO-Compat" "perl-Package-Generator" "perl-Params-Check" "perl-Params-Util" "perl-parent" "perl-PathTools" \
            "perl-Perl-OSType" "perl-perlfaq" "perl-PerlIO-via-QuotedPrint" "perl-Pod-Checker" "perl-Pod-Escapes" "perl-Pod-Parser" \
            "perl-Pod-Perldoc" "perl-Pod-Simple" "perl-Pod-Usage" "perl-podlators" "perl-Scalar-List-Utils" "perl-Socket" "perl-Software-License" \
            "perl-Storable" "perl-Sub-Exporter" "perl-Sub-Install" "perl-Sys-Syslog" "perl-Term-ANSIColor" "perl-Term-Cap" "perl-Test-Harness" \
            "perl-Test-Simple" "perl-Text-Balanced" "perl-Text-Diff" "perl-Text-Glob" "perl-Text-ParseWords" "perl-Text-Tabs+Wrap" \
            "perl-Text-Template" "perl-Thread-Queue" "perl-threads" "perl-threads-shared" "perl-Time-HiRes" "perl-Time-Local" \
            "perl-Unicode-Collate" "perl-Unicode-Normalize" "perl-URI" "perl-version" \
            "cmake" "xapian-core" "libtool" "doxygen" ) 

debug() {
   echo "$@" 1>&2
#    return
}

#usage: containsElement "blaha" "${array[@]}"
# returns 0 (true) if element is in array
# returns 1 (false) if element is not in array
containsElement () {
  local e
  for e in "${@:2}"; do [ "$e" == "$1" ] && return 0; done
  return 1
}

gather_modulemd_rpms() {
   if [ "${1}" != "" ]; then
      debug "gather_modulemd_rpms adding ${1} to rpm list"
      echo "            ${1}:" >> $modulerpmsfile
      echo "                rationale: ${@:2}" >> $modulerpmsfile
      echo "                ref: f26" >> $modulerpmsfile
   fi
}

gather_profile() {
   if [ "${1}" != "" ]; then
      debug "gather_profile adding ${1} to profile"
      echo "                - ${1}" >> $moduleprofilefile
   fi
}

gather_api() {
   if [ "${1}" != "" ]; then
      debug "gather_api adding ${1} to api"
      echo "            - ${1}" >> $moduleapifile
   fi
}

# "acl at attr audit babeltrace basesystem bash bc binutils byacc ...."
wget -N https://raw.githubusercontent.com/fedora-modularity/base-runtime/master/api.x86_64
brtsrpms=(`grep -v -e "^+\|^*\|!" api.x86_64 | sed -e "s/-[^-]*-[^-]*//"`)
brtrpms=(`grep -e "^+\|^*" api.x86_64  | cut -f 2 | sed -e "s/-[^-]*-[^-]*$//"`)

for binaryrpm in $*; do
   debug "working on $binaryrpm"
   if containsElement "$binaryrpm" "${brtrpms[@]}" ; then
      debug "$binaryrpm is already in BRT"
      continue
   fi
   if containsElement "$binaryrpm" "${modulerpms[@]}" ; then
      debug "$binaryrpm is already in the list of deps for this module"
      continue
   fi
   if containsElement "$binaryrpm" "${solvedbuilddeps[@]}" ; then
      debug "$binaryrpm is already in common-build-deps or in bootstrap"
      continue
   fi
   binaryrpm_srpm=`dnf repoquery --releasever 26 -q --qf "%{SOURCERPM}" --whatprovides "$binaryrpm" 2>/dev/null | tail -1 | sed -e "s/-[^-]*-[^-]*.src.rpm//"`
   if [ "$binaryrpm_srpm" == "" ]; then
      debug "no source rpm found for $binaryrpm"
      continue
   fi
   gather_profile $binaryrpm
   gather_api $binaryrpm
   if containsElement "$binaryrpm" "${modulerpms[@]}" ; then
      gather_modulemd_rpms $binaryrpm_srpm "Component for shared userspace - $binaryrpm."
      modulerpms+=($binaryrpm_srpm)
   fi
   # deps has a list of dependencies that the source RPM of a package given on the cmdline has
   deps=`repoquery --enablerepo fedora-source  --releasever 26 --arch src -q --requires $binaryrpm_srpm 2>/dev/null | sed -e "s/ .*$//"`
   for dep in $deps; do
      grep -q "$dep" $alreadyprocessed && continue
      echo "$dep" >> $alreadyprocessed
      # bdep is a binary package that provides one of the source rpm dependencies
      bdep=`repoquery --releasever 26 -q --whatprovides "$dep" 2>/dev/null | tail -1 | sed -e "s/-[^-]*-[^-]*$//"`
      if containsElement "$bdep" "${brtrpms[@]}" ; then
         debug "$bdep is already in BRT"
         continue
      fi

      if containsElement "$bdep" "${modulerpms[@]}" ; then
         debug "$bdep is already in the list of deps for this module"
         continue
      fi
#      modulerpms+=($bdep)
      # sdep is a source rpm that provides one of the dependencies of a package given on the cmdline (its srpm) 
      sdep=`repoquery --releasever 26 -q --qf "%{SOURCERPM}" --whatprovides "$dep" 2>/dev/null | tail -1 | sed -e "s/-[^-]*-[^-]*.src.rpm//"`
      if containsElement "$sdep" "${solvedbuilddeps[@]}" ; then
         debug "$sdep already in common-build-deps or in bootstrap"
         continue
      fi
      if ! containsElement "$sdep" "${modulerpms[@]}" ; then
	 debug "$sdep not in modulerpms, adding"
         modulerpms+=($sdep)
         gather_modulemd_rpms $sdep "Requirement for ${binaryrpm}."
         continue
      fi
   done
done


cat << EOT
document: modulemd
version: 1
data:
    summary: Shared Userspace Module
    description: A module that contains libraries, binaries, etc
                 that are shared between all other modules.
    license:
        module: [ MIT ]
    dependencies:
        buildrequires:
            base-runtime: master
            perl: master
            common-build-dependencies-bootstrap: master
            common-build-dependencies: master
        requires:
            base-runtime: master
            perl: master
    references:
        community: https://fedoraproject.org/wiki/Modularity
        documentation: https://fedoraproject.org/wiki/Fedora_Packaging_Guidelines_for_Modules
        tracker: https://taiga.fedorainfracloud.org/project/modularity
    profiles:
        default:
            rpms:
EOT
cat $moduleprofilefile
cat << EOT
    api:
        rpms:
EOT
cat $moduleapifile
cat << EOT
    components:
        rpms:
            xapian-core:
                rationale:  Build dep of doxygen.
                ref: private-karsten-modularity
                buildorder: 1
            cmake:
                rationale: Build dep for many packages.
                ref: private-karsten-modularity
                buildorder: 1
            libtool:
                rationale: Build dep for many packages.
                ref: private-karsten-modularity
                buildorder: 1
            bison:
                rationale: Build dep for many packages.
                ref: f26
                buildorder: 1
            doxygen:
                rationale: Build dep for many packages.
                ref: private-karsten-modularity
                buildorder: 2
EOT
cat $modulerpmsfile

rm -f $moduleprofilefile $moduleapifile $modulerpmsfile $alreadyprocessed

