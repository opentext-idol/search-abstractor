#
# Copyright 2024-2025 Open Text.
#
# The only warranties for products and services of Open Text and its
# affiliates and licensors ("Open Text") are as may be set forth in the
# express warranty statements accompanying such products and services.
# Nothing herein should be construed as constituting an additional
# warranty. Open Text shall not be liable for technical or editorial
# errors or omissions contained herein. The information contained herein
# is subject to change without notice.
#
# Except as specifically indicated otherwise, this document contains
# confidential information and a valid license is required for possession,
# use or copying. If this work is provided to the U.S. Government,
# consistent with FAR 12.211 and 12.212, Commercial Computer Software,
# Computer Software Documentation, and Technical Data for Commercial Items
# are licensed to the U.S. Government under vendor's standard commercial
# license.
#

{{- define "auth.urlNorm" -}}
{{ .external.protocol }}://{{ .external.host -}}
  {{- if not (or (eq "80" (.external.port | toString)) (eq "443" (.external.port | toString))) -}}
    :{{- .external.port -}}{{- end -}}
  {{- if .path -}}/{{trimAll "/" .path }}{{- end -}}
{{- end -}}
