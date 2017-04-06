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

debug() {
   echo "$@" 1>&2
#    return
}

#usage: containsElement "blaha" "${array[@]}"
containsElement () {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

gather_modulemd_rpms() {
   if [ "${1}" != "" ]; then
      debug "gather_modulemd_rpms adding $binaryrpm_srpm to rpm list"
      echo "            ${1}:" >> $modulerpmsfile
      echo "                rationale: ${@:2}" >> $modulerpmsfile
      echo "                ref: f26" >> $modulerpmsfile
   fi
}

gather_profile() {
   if [ "${1}" != "" ]; then
      debug "gather_profile adding $binaryrpm to profile"
      echo "                - ${1}" >> $moduleprofilefile
   fi
}

gather_api() {
   if [ "${1}" != "" ]; then
      debug "gather_api adding $binaryrpm to api"
      echo "            - ${1}" >> $moduleapifile
   fi
}

# "acl at attr audit babeltrace basesystem bash bc binutils byacc ...."
wget -N https://raw.githubusercontent.com/fedora-modularity/base-runtime/master/api.txt
brtsrpms=(`grep -v -e "^+\|^*\|!" api.txt | sed -e "s/-[^-]*-[^-]*//"`)
brtrpms=(`grep -e "^+\|^*" api.txt  | cut -f 2 | sed -e "s/-[^-]*-[^-]*$//"`)

for binaryrpm in $*; do
   debug "working on $binaryrpm"
   if containsElement "$binaryrpm" "${brtrpms[@]}" -eq 1 ; then
      debug "$binaryrpm is already in BRT"
      continue
   fi
   if containsElement "$binaryrpm" "${modulerpms[@]}" -eq 1 ; then
      debug "$binaryrpm is already in the list of deps for this module"
      continue
   fi
   binaryrpm_srpm=`dnf repoquery --releasever 26 -q --qf "%{SOURCERPM}" --whatprovides "$binaryrpm" 2>/dev/null | tail -1 | sed -e "s/-[^-]*-[^-]*.src.rpm//"`
   if [ "$binaryrpm_srpm" == "" ]; then
      debug "no source rpm found for $binaryrpm"
      continue
   fi
   gather_profile $binaryrpm
   gather_api $binaryrpm
   if containsElement "$binaryrpm" "${modulerpms[@]}" -eq 1 ; then
      gather_modulemd_rpms $binaryrpm_srpm "Component for shared userspace - $binaryrpm."
      modulerpms+=($binaryrpm_srpm)
   fi
   # FIXME recursive: ?
   #deps=`dnf repoquery --releasever 26 --arch src -q --requires $binaryrpm_srpm 2>/dev/null | sed -e "s/ .*$//"`
   # dnf repoquery is broken wrt. src rpm requirements, use yum repoquery here:
   deps=`repoquery --enablerepo fedora-source  --releasever 26 --arch src -q --requires $binaryrpm_srpm 2>/dev/null | sed -e "s/ .*$//"`
   #debug "deps: $deps"
   for dep in $deps; do
      grep -q "$dep" $alreadyprocessed && continue
      echo "$dep" >> $alreadyprocessed
      bdep=`dnf repoquery --releasever 26 -q --whatprovides "$dep" 2>/dev/null | tail -1 | sed -e "s/-[^-]*-[^-]*$//"`
      debug "working on $bdep"
      if containsElement "$bdep" "${brtrpms[@]}" -eq 1 ; then
         debug "$bdep is already in BRT"
         continue
      fi

      if containsElement "$bdep" "${modulerpms[@]}" -eq 1 ; then
         debug "$bdep is already in the list of deps for this module"
         continue
      fi
      debug "adding 5 $bdep to modulerpms"
      modulerpms+=($bdep)
      sdep=`dnf repoquery --releasever 26 -q --qf "%{SOURCERPM}" --whatprovides "$dep" 2>/dev/null | tail -1 | sed -e "s/-[^-]*-[^-]*.src.rpm//"`
      if containsElement "sdep" "${modulerpms[@]}" -ne 1 ; then
         gather_modulemd_rpms $sdep "Requirement for ${binaryrpm}."
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
            base_runtime: master
        requires:
            base_runtime: master
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
EOT
cat $modulerpmsfile

rm -f $moduleprofilefile $moduleapifile $modulerpmsfile $alreadyprocessed

