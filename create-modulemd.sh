#!/bin/bash
#
#TODO:  output api
#
# Walkthrough:
# - get a list of srpm package names that are included in BRT
# - loop until ".end" got entered:
#   - read newpackage from stdin
#   - check if newpackage is in srpms list > next loop
#   - check if newpackage is in module rpm list > next loop
#   - get build deps from newpackage
#   - loop over build deps:
#     - check if build dep is in srpms list > next loop
#     - check if build dep is in module rpm list > next loop
#     - otherwise add build dep to module rpm list
#       and output modulemd snipped with rpm name and rationale


## #get a list of build deps from a certain binary rpm:
## repoquery --disablerepo=Dropbox --releasever 26 --requires --recursive --resolve  --qf "%{SOURCERPM}" vim-minimal | sort -n | uniq

binaryrpm=""
modulerpms=()
modulerpmsfile=`mktemp`
moduleapifile=`mktemp`
moduleprofilefile=`mktemp`


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
      echo "            ${1}:" >> $modulerpmsfile
      echo "                rationale: ${@:2}" >> $modulerpmsfile
      echo "                ref: f26" >> $modulerpmsfile
   fi
}

gather_profile() {
   if [ "${1}" != "" ]; then
      echo "                - ${1}" >> $moduleprofilefile
   fi
}

gather_api() {
   if [ "${1}" != "" ]; then
      echo "            - ${1}" >> $moduleapifile
   fi
}


# "acl at attr audit babeltrace basesystem bash bc binutils byacc ...."
srpms=(`echo 'rpm -qp --qf "%{SOURCERPM}\n" /srv/groups/modularity/repos/base-runtime/26/*.rpm | sed -e "s/-[^-]*-[^-]*.base_runtime_master_20170308145737.src.rpm$//"| sort -n | uniq' | ssh fedorapeople.org 2>/dev/null`)

for binaryrpm in $*; do
   # make sure it is the name of an srpm:
   binaryrpm_srpm=`repoquery --releasever 26 -q --qf "%{SOURCERPM}" $binaryrpm 2>/dev/null | tail -1 | sed -e "s/-[^-]*-[^-]*.src.rpm//"`
   if [ "$binaryrpm_srpm" == "" ]; then
      debug "no source rpm found for $binaryrpm"
      continue
   fi
   binaryrpm=$binaryrpm_srpm
   if containsElement "$binaryrpm" "${srpms[@]}" -eq 1 ; then
      debug "$binaryrpm is already in BRT"
      continue
   fi

   if containsElement "$binaryrpm" "${modulerpms[@]}" -eq 1 ; then
      debug "$binaryrpm is already in the list of deps for this module"
      continue
   fi
   modulerpms+=($binaryrpm)
   gather_profile $binaryrpm
   gather_api $binaryrpm
   gather_modulemd_rpms $binaryrpm "Component for shared userspace."
   deps=`repoquery --enablerepo=fedora-source --releasever 26 --archlist=src -q --requires --recursive $binaryrpm 2>/dev/null | sed -e "s/ .*$//"`
   #debug "deps: $deps"
   for dep in $deps; do
      sdep=`repoquery --releasever 26 -q --qf "%{SOURCERPM}" --whatprovides $dep 2>/dev/null | tail -1 | sed -e "s/-[^-]*-[^-]*.src.rpm//"`
      #debug "dep: x${sdep}x"
      if containsElement "$sdep" "${srpms[@]}" -eq 1 ; then
         debug "$sdep is already in BRT"
         continue
      fi

      if containsElement "$sdep" "${modulerpms[@]}" -eq 1 ; then
         debug "$sdep is already in the list of deps for this module"
         continue
      fi
      modulerpms+=($sdep)
      gather_profile $sdep
      gather_modulemd_rpms $sdep "Requirement for ${binaryrpm}."
   done
done
echo ${modulerpms[@]}

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

rm -f $moduleprofilefile $moduleapifile $modulerpmsfile
