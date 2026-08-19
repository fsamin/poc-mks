{
  "realm": "git-deploy",
  "enabled": true,
  "registrationAllowed": false,
  "roles": {
    "realm": [
      {
        "name": "git-deploy-admin",
        "description": "git-deploy platform administrator: every tenant, tenant administration"
      }
    ]
  },
  "groups": [
    {
      "name": "tenants",
      "path": "/tenants",
      "subGroups": []
    }
  ],
  "users": [
    {
      "username": "service-account-git-deploy-operator",
      "enabled": true,
      "serviceAccountClientId": "git-deploy-operator",
      "clientRoles": {
        "realm-management": ["manage-users"]
      }
    }
  ],
  "clients": [
    {
      "clientId": "git-deploy-cli",
      "name": "git-deploy CLI",
      "enabled": true,
      "publicClient": true,
      "standardFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "attributes": {
        "oauth2.device.authorization.grant.enabled": "true"
      },
      "protocolMappers": [
        {
          "name": "groups",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-group-membership-mapper",
          "consentRequired": false,
          "config": {
            "full.path": "true",
            "claim.name": "groups",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "userinfo.token.claim": "true"
          }
        },
        {
          "name": "realm-roles",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-realm-role-mapper",
          "consentRequired": false,
          "config": {
            "claim.name": "realm_access.roles",
            "multivalued": "true",
            "jsonType.label": "String",
            "id.token.claim": "true",
            "access.token.claim": "true"
          }
        },
        {
          "name": "audience",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-audience-mapper",
          "consentRequired": false,
          "config": {
            "included.client.audience": "git-deploy-cli",
            "id.token.claim": "false",
            "access.token.claim": "true"
          }
        }
      ]
    },
    {
      "clientId": "oauth2-proxy",
      "name": "oauth2-proxy (browser sessions of the git-deploy UI)",
      "enabled": true,
      "publicClient": false,
      "secret": "${oauth2_proxy_client_secret}",
      "standardFlowEnabled": true,
      "directAccessGrantsEnabled": false,
      "redirectUris": ["https://${gitdeploy_host}/oauth2/callback"],
      "webOrigins": ["https://${gitdeploy_host}"],
      "protocolMappers": [
        {
          "name": "groups",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-group-membership-mapper",
          "consentRequired": false,
          "config": {
            "full.path": "true",
            "claim.name": "groups",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "userinfo.token.claim": "true"
          }
        },
        {
          "name": "realm-roles",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-realm-role-mapper",
          "consentRequired": false,
          "config": {
            "claim.name": "realm_access.roles",
            "multivalued": "true",
            "jsonType.label": "String",
            "id.token.claim": "true",
            "access.token.claim": "true"
          }
        },
        {
          "name": "audience",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-audience-mapper",
          "consentRequired": false,
          "config": {
            "included.client.audience": "oauth2-proxy",
            "id.token.claim": "true",
            "access.token.claim": "true"
          }
        }
      ]
    },
    {
      "clientId": "git-deploy-operator",
      "name": "git-deploy operator (tenant group management)",
      "enabled": true,
      "publicClient": false,
      "secret": "${operator_client_secret}",
      "standardFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "serviceAccountsEnabled": true
    }
  ]
}
