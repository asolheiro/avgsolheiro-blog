+++
authors = ["Armando Solheiro"]
title = "Git Releases"
date = "2025-03-29"
description = "Um caso de uso para criação de Releases no GitLab e no GitHub utilizando esteiras de integração"
tags = [
    "git",
    "releases",
    "github",
    "gitlab",
    "pipeline",
    "CI/CD",
]
categories = [
    "pipeline",
]
+++

## 1\. Introdução

Recentemente tive a oportunidade de escrever uma CLI em Go para automatizar a produção de relatórios com dados retirados do **Gita**, uma plataforma de monitoramento e gerenciamento de clusters desenvolvida pela empresa na qual trabalho.

A CLI atende muito bem seu objetivo, mas, por se tratar de uma empresa com foco em Infraestrutura achamos mais adequado fornecer o binário já construído, ao invés de delegar que o usuário clone o repositório e construa o artefato final.

Para centralizar a distribuição dessa maneira, ambas plataformas de hospedagem de código, GitHub e GitLab, permitem disponibilizar *releases*/lançamentos para o usuário no mesmo repositório onde o código fonte é mantido.

Basicamente, o que precisamos é de uma esteira que possua dois passos:

1. Construção (*build*);
    
2. Disponibilização (*Release*)
    

Tudo isso feito utilizando as ferramentas de CI/CD das plataformas, assunto que tratarei neste texto.

## 2\. GitHub Actions

### 2.1. Configuração inicial

Para o GitHub Action, iniciamos definindo as configurações da *pipeline*:

```yaml
name: Release app binaries
on:
  push:
    tags:
      - 'v*'
permissions:
  contents: write
```

Nesse caso, definimos três informações:

* `name`: escolhendo o nome que a esteira receberá no GitHub;
    
* `on.push.tags: ['v*']`: definindo que a esteira será acionada toda vez que houver um push em qualquer tag;
    
* `permissions.contents: write`: para permitir que lá na frente o *Actions* possa escrever no repositório e adicionar as releases.
    

> Nota: Além dessa configuração, é necessário que o repositório esteja com *Read and Write* configurado em "Settings >> Actions >> General >> Workflow permission"

Além disso, configuramos o ambiente utilizando para os processos:

```yaml
jobs:
  build:
    name: Build and Release
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        
      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.23.5'
          
      - name: Get version from tag
        id: get_version
        run: echo "VERSION=${GITHUB_REF#refs/tags/}" >> $GITHUB_ENV
```

* Utilizamos `jobs.build.runs-on: ubuntu-latest` para dizer que o processo (`job.build`) será executado em cima da última versão do Ubuntu;
    
* `jobs.steps[0].uses: actions/checkout@v4` para copiar o conteúdo do repositório para o agente;
    
* `jobs.steps[1].uses: actions/setup-go@v5` para definir a versão de Go utilizada, `1.23.5`, neste caso;
    
* `jobs.steps[2]` para consumir a tag do push.
    

### 2.2. Construção dos binários

Para criar os binários, utilizamos as variáveis `GOOS` e `GOARCH` para definir, respectivamente, o sistema operacional e a arquitetura da construção:

| `GOOS` | `GOARCH` | binário resultante |
| --- | --- | --- |
| linux | amd64 | ghc-v1.0.0-linux-amd64 |
| linux | arm64 | ghc-v1.0.0-linux-arm64 |
| windows | amd64 | ghc-v1.0.0-windows-amd64 |

Elas são utilizadas em comandos de construção padrão da linguagem, com suas saídas direcionadas para o diretório `./dist`.

```yaml
- name: Build binaries
  run: |
    # Create dist directory
    mkdir -p dist
    
    # Build for each platform
    GOOS=linux GOARCH=amd64 go build -o "dist/${{ github.event.repository.name }}-${{ env.VERSION }}-linux-amd64" -ldflags="-X 'main.Version=${{ env.VERSION }}'" ./main.go
    GOOS=linux GOARCH=arm64 go build -o "dist/${{ github.event.repository.name }}-${{ env.VERSION }}-linux-arm64" -ldflags="-X 'main.Version=${{ env.VERSION }}'" ./main.go
    GOOS=windows GOARCH=amd64 go build -o "dist/${{ github.event.repository.name }}-${{ env.VERSION }}-windows-amd64.exe" -ldflags="-X 'main.Version=${{ env.VERSION }}'" ./main.go
    
    # Generate checksums
    cd dist
    sha256sum * > checksums.txt
    cd ..
```

### 2.3. Disponibilizando os artefatos

A distribuição dos artefatos produzidos é feita utilizando um action desenvolvido pela comunidade, o [`softprops/action-gh-release`](https://github.com/softprops/action-gh-release). Utilizando ele, temos apenas o trabalho de informar valores já guardados em variáveis do ambiente e indicar o endereço do artefato; nesse caso, todos dentro do diretório `dist/`

```yaml
- name: Create Release
  id: create_release
  uses: softprops/action-gh-release@v1
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  with:
    name: Release ${{ env.VERSION }}
    draft: false
    prerelease: false
    files: |
      dist/*
```

### 2.4. Push

Definida esteira, enviamos o conteúdo para o repositório:

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git add .
git commit -m "Adding pipeline to make releases available"
git push github v1.0.0
```

E verificamos o resultado:

![](https://cdn.hashnode.com/res/hashnode/image/upload/v1740182709492/1c7be34e-6441-49aa-aace-0016491b2d1a.png align="center")

## 3\. GitLab CI

### 3.1. Configurações iniciais

No GitLab também começamos definindo informações:

```yaml
variables:
  REPO_NAME: ghc
  VERSION: ${CI_COMMIT_TAG}
  PACKAGE_NAME: ${REPO_NAME}
  PACKAGE_REGISTRY_URL: "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/${PACKAGE_NAME}/${VERSION}"

stages:
  - build
  - upload
  - release
```

Já nessa plataforma, dividimos a execução em três estágios, construção, upload e lançamento.

### 3.1. Construção dos binários

A etapa de construção é essencialmente a mesma feita para o GitHub: o comando padrão executado diversas vezes para gerar um artefato para cada combinação de sistema operacional e arquitetura.

```yaml
build:
  stage: build
  image: golang:latest
  rules:
    - if: $CI_COMMIT_TAG
  script:
    - mkdir -p dist
    # Linux AMD64
    - GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o "dist/${REPO_NAME}-${VERSION}-linux-amd64" -ldflags="-X 'main.Version=${VERSION}'" ./main.go
    - cd dist && sha256sum "${REPO_NAME}-${VERSION}-linux-amd64" > "${REPO_NAME}-${VERSION}-linux-amd64.sha256" && cd ..
    
    # Linux ARM64
    - GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o "dist/${REPO_NAME}-${VERSION}-linux-arm64" -ldflags="-X 'main.Version=${VERSION}'" ./main.go
    - cd dist && sha256sum "${REPO_NAME}-${VERSION}-linux-arm64" > "${REPO_NAME}-${VERSION}-linux-arm64.sha256" && cd ..
    
    # Windows AMD64
    - GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -o "dist/${REPO_NAME}-${VERSION}-windows-amd64.exe" -ldflags="-X 'main.Version=${VERSION}'" ./main.go
    - cd dist && sha256sum "${REPO_NAME}-${VERSION}-windows-amd64.exe" > "${REPO_NAME}-${VERSION}-windows-amd64.exe.sha256" && cd ..
    
  artifacts:
    paths:
      - dist/
    expire_in: 1 week
```

Note que, não definimos o `on.push.tags: 'v*'` para explicitar que o gatilho da esteira é um `push` em qualquer tag, mas é possível ver nesse estágio (e em todos os seguintes) temos `build.rules[0].if: $CI_COMMIT_TAG:` indicando o mesmo gatilho de ativação.

Outro ponto interessante é `build.artifacts.expire_in: 1 week`. Nesse campo, temos a possibilidade de definir por quanto tempo os artefatos devem permanecer disponíveis na esteira.

### 3.2. Upload

Diferente do GitHub, no qual adicionamos os artefatos direto no lançamento de versões, aqui utilizamos esse estágio intermediário para salvar as saídas.

```yaml
upload:
  stage: upload
  image: curlimages/curl:latest
  rules:
    - if: $CI_COMMIT_TAG
  dependencies:
    - build
  script:
    - |
      for file in dist/*; do
        filename=$(basename $file)
        echo "Uploading $filename to Package Registry..."
        curl --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
          --upload-file $file \
          "${PACKAGE_REGISTRY_URL}/${filename}"
      done
```

Os binários produzidos no estágio de construção são salvos em um "*registry*", definido lá em cima, nas configurações iniciais.

### 3.3. Distribuição dos artefatos

Para realizar a distribuição dos binários produzidos utilizamos o `release-cli`, ferramenta do GitLab CI indicada na própria [documentação oficial](https://docs.gitlab.com/user/project/releases/release_cli/)

```yaml
release:
  stage: release
  image: registry.gitlab.com/gitlab-org/release-cli:latest
  rules:
    - if: $CI_COMMIT_TAG
  needs:
    - upload
  script:
    - |

      assets_links=""
      
      # Linux AMD64
      assets_links="$assets_links --assets-link={\"name\":\"${REPO_NAME}-${VERSION}-linux-amd64\",\"url\":\"${PACKAGE_REGISTRY_URL}/${REPO_NAME}-${VERSION}-linux-amd64\"}"
      assets_links="$assets_links --assets-link={\"name\":\"${REPO_NAME}-${VERSION}-linux-amd64.sha256\",\"url\":\"${PACKAGE_REGISTRY_URL}/${REPO_NAME}-${VERSION}-linux-amd64.sha256\"}"
      
      # Linux ARM64
      assets_links="$assets_links --assets-link={\"name\":\"${REPO_NAME}-${VERSION}-linux-arm64\",\"url\":\"${PACKAGE_REGISTRY_URL}/${REPO_NAME}-${VERSION}-linux-arm64\"}"
      assets_links="$assets_links --assets-link={\"name\":\"${REPO_NAME}-${VERSION}-linux-arm64.sha256\",\"url\":\"${PACKAGE_REGISTRY_URL}/${REPO_NAME}-${VERSION}-linux-arm64.sha256\"}"
      
      # Windows AMD64
      assets_links="$assets_links --assets-link={\"name\":\"${REPO_NAME}-${VERSION}-windows-amd64.exe\",\"url\":\"${PACKAGE_REGISTRY_URL}/${REPO_NAME}-${VERSION}-windows-amd64.exe\"}"
      assets_links="$assets_links --assets-link={\"name\":\"${REPO_NAME}-${VERSION}-windows-amd64.exe.sha256\",\"url\":\"${PACKAGE_REGISTRY_URL}/${REPO_NAME}-${VERSION}-windows-amd64.exe.sha256\"}"
    
      
      # Create release with all assets
      release-cli create \
        --name "Release ${VERSION}" \
        --tag-name $CI_COMMIT_TAG \
        --description "Release ${VERSION}" \
        $assets_links
```

Essencialmente, o que fazemos aqui é definir a URL dos artefatos e executar o comando uma vez para cada um.

### 3.4. Push

Definida esteira, enviamos o conteúdo para o repositório:

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git add .
git commit -m "Adding pipeline to make releases available"
git push gitlab v1.0.0
```

E conferimos o resultado:

![](https://cdn.hashnode.com/res/hashnode/image/upload/v1740182732753/bf1bbe1f-2de5-4153-a2ae-b74563abd5a4.png align="center")

## 4\. Considerações finais

A ideia inicial era disponibilizar o aplicativo para máquinas macOS também, entretanto para que a distribuição ficasse redonda, sem nenhuma falha, era necessário certificar a aplicação com um software Apple que custa uma quantidade considerável.

Por esse motivo retirei SO Apple da lista, apesar de o processo de construção ser exatamente o mesmo.