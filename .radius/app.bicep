extension radius

param environment string

@secure()
param postgresPassword string

@description('Password/token for the OCI registry the containerImages recipe pushes to.')
@secure()
param registryPassword string

@description('Username for the OCI registry the containerImages recipe pushes to.')
@secure()
param registryUsername string

resource pgwebApp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'pgweb'
  properties: {
    environment: environment
  }
}

resource postgresData 'Radius.Compute/persistentVolumes@2025-08-01-preview' = {
  name: 'postgres-data'
  properties: {
    environment: environment
    application: pgwebApp.id
    codeReference: 'docker-compose.yml#L9'
    allowedAccessModes: 'ReadWriteOnce'
    sizeInGib: 10
  }
}

resource postgresCredentials 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'postgres-credentials'
  properties: {
    environment: environment
    application: pgwebApp.id
    codeReference: 'docker-compose.yml#L10'
    data: {
      password: {
        value: postgresPassword
      }
    }
  }
}

resource registryCreds 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'radius-ghcr-registry-creds'
  properties: {
    environment: environment
    application: pgwebApp.id
    codeReference: '.radius/app.bicep#L48'
    data: {
      password: {
        value: registryPassword
      }
      username: {
        value: registryUsername
      }
    }
  }
}

resource pgwebImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'pgweb-image'
  properties: {
    environment: environment
    application: pgwebApp.id
    codeReference: 'Dockerfile#L4'
    build: {
      source: 'git::https://github.com/willdavsmith/pgweb.git?ref=e4858a16d8e032730055289596ea9059a91bca64'
      args: {
        BUILDKIT_CONTEXT_KEEP_GIT_DIR: '1'
      }
      platforms: [
        'linux/amd64'
      ]
    }
  }
  dependsOn: [
    registryCreds
  ]
}

resource pgwebContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'pgweb'
  properties: {
    environment: environment
    application: pgwebApp.id
    codeReference: 'pkg/cli/cli.go#L297'
    containers: {
      pgweb: {
        image: pgwebImage.properties.imageReference
        command: [
          '/bin/sh'
          '-c'
        ]
        args: [
          'exec /usr/bin/pgweb --bind=0.0.0.0 --listen=8081 --host="$PGWEB_POSTGRES_HOST" --port=5432 --user=pgweb --pass="$POSTGRES_PASSWORD" --db=pgweb --ssl=disable --open-retry=20 --open-retry-delay=3'
        ]
        env: {
          PGWEB_POSTGRES_HOST: {
            value: postgresContainer.properties.hosts[postgresContainer.name]
          }
          POSTGRES_PASSWORD: {
            valueFrom: {
              secretKeyRef: {
                secretName: postgresCredentials.name
                key: 'password'
              }
            }
          }
        }
        livenessProbe: {
          tcpSocket: {
            port: 8081
          }
        }
        ports: {
          web: {
            containerPort: 8081
          }
        }
        readinessProbe: {
          tcpSocket: {
            port: 8081
          }
        }
      }
    }
  }
}

resource postgresContainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'postgres'
  properties: {
    environment: environment
    application: pgwebApp.id
    codeReference: '.radius/app.bicep#L135'
    containers: {
      postgres: {
        image: 'postgres:18'
        env: {
          POSTGRES_DB: {
            value: 'pgweb'
          }
          POSTGRES_PASSWORD: {
            valueFrom: {
              secretKeyRef: {
                secretName: postgresCredentials.name
                key: 'password'
              }
            }
          }
          POSTGRES_USER: {
            value: 'pgweb'
          }
        }
        livenessProbe: {
          exec: {
            command: [
              'pg_isready'
              '-U'
              'pgweb'
              '-h'
              '127.0.0.1'
            ]
          }
        }
        ports: {
          database: {
            containerPort: 5432
          }
        }
        readinessProbe: {
          exec: {
            command: [
              'pg_isready'
              '-U'
              'pgweb'
              '-h'
              '127.0.0.1'
            ]
          }
        }
        volumeMounts: [
          {
            volumeName: 'data'
            mountPath: '/var/lib/postgresql'
          }
        ]
      }
    }
    volumes: {
      data: {
        persistentVolume: {
          resourceId: postgresData.id
          accessMode: 'ReadWriteOnce'
        }
      }
    }
  }
}
