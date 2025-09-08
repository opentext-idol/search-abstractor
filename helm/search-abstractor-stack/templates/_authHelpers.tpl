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

{{/* Endpoint where components should contact OTDS API */}}
{{- define "otds.endpoint" -}}
{{- $root := get . "root" | required "missing root" -}}
{{- $auth := get . "auth" | required "missing auth" -}}
{{- include "auth.urlNorm" (dict "external" $auth.external "path" $auth.otdsws.ingress.prependPath) -}}
{{- end -}}

{{/* Configure SSLMethod for OTDS API */}}
{{- define "otds.sslmethod" -}}
{{- $root := get . "root" | required "missing root" -}}
{{- $auth := get . "auth" | required "missing auth" -}}
{{- $method := get . "method" | default "Negotiate" -}}
{{- get $auth.external "protocol" | eq "https" | ternary $method "None" -}}
{{- end -}}

{{/* Add configuration settings for Community OTDS Security module */}}
{{- define "otds.securitylib.config" -}}
{{- $root := get . "root" | required "missing root" -}}
{{- $auth := get . "auth" | required "missing auth" -}}
{{- $sslsettings := get . "sslsettings" | default "SSLSettingsOTDS" -}}
OTDSHost={{ $auth.external.host }}
OTDSPort={{ $auth.external.port }}
{{- if $auth.otdsws.ingress.prependPath }}
OTDSPath={{ trimAll "/" $auth.otdsws.ingress.prependPath }}
{{- end -}}
{{- if eq (get $auth.external "protocol") "https" }}
SSLConfigOTDS={{ $sslsettings }}
{{- end -}}
{{- if $auth.userSecurity.jwtUserField }}
OTDSUserField={{ $auth.userSecurity.jwtUserField }}
{{- end -}}
{{- if not $auth.userSecurity.resourceId }}
RequireResourceId=FALSE
{{- end -}}
{{- end -}}