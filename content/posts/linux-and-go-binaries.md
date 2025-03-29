+++
authors = ["Armando Solheiro"]
title = "Distribuições linux e binários Go"
date = "2025-03-29"
description = "Testes com tamanho de imagens utilizando imagens base e formas de compilação de código"
tags = [
    "linux",
    "alpine",
    "scratch",
    "go",
    "golang",
    "binaries",
]
categories = [
    "linux",
    "go",
]
series = ["Theme Demo"]
+++

Na minha humilde opinião, um dos motivos que fazem programar em Go ser tão bom é a possibilidade de gerar um binário para execução com a facilidade de um `go build .`no terminal.

Essa pequena prática traz diversas vantagens para nós desenvolvedores:

* os binários podem ser usados como forma de documentar as versões do código-fonte;
    
* facilitamos o deploy da aplicação;
    
* otimizamos o desempenho ao compilar para determinada arquitetura;
    
* binários são mais difíceis de ler e alterar, logo aumentamos a segurança ao utilizá-los;
    
* trazemos mais independência do ambiente de desenvolvimento;
    
* temos mais eficiência no uso de recursos computacionais.
    

Poderíamos escrever arquivos inteiros sobre as vantagens de implementações usando binários, mas por hora isso é o bastante.

Para exemplificar, nesse artigo usaremos um código-fonte básico de uma API que retorna apenas um “Olá, mundo!”:

```go
package main

import (
"fmt"
"log"
"net/http"
)

func main() {
http.HandleFunc("/", func(rw http.ResponseWriter, r *http.Request) {
fmt.Fprintf(rw, "Olá, mundo\n")
})

log.Fatal(http.ListenAndServe(":8080", nil))
}
```

que após compilado rende um arquivo binário de miseráveis 6.8 MB:

![](https://cdn.hashnode.com/res/hashnode/image/upload/v1731102420532/631c21b9-643c-4826-ac12-568112e3e5a4.png)

Código-fonte main.go e seu binário, main, resultante

os quais ainda podemos reduzir mais se utilizarmos *linker flags —* que se comunicam direto com o linker, ferramenta que é responsável por vincular o código-fonte ao binário. Esse assunto rende uma discussão inteira, então não alongaremos mais.

Nesse caso, podemos fazer a build com duas flags em específico:

`-s` : omitirá a tabela de símbolos e informações para debug

`-w` : omite a tabela DWARF para debug

As quais passaremos no momento da compilação:

```bash
$ go build -ldflags="-s -w"
```

e nos permite reduzir nosso binário em 2.8MB, ou cerca de 16%, neste caso. Há situações em que esse número pode ser maior

![](https://cdn.hashnode.com/res/hashnode/image/upload/v1731102421936/c9f6baa8-b0b2-466c-83f8-f3e29fce2f3b.png)

Tamanho do código-fonte e do binário resultante usando as linker flags

Vale salientar, também, que Go naturalmente cria binários compatíveis com a máquina em que estamos compilamos o código, mas isso não nos impede de fazer alterações visando resultados feitos para rodar em outros tipos sistemas operacionais e arquiteturas.

Essas informações especificamente são guardadas pelo compilador Go na forma de variáveis de sistema; basta executar `go env GOOS GOARCH` na linha de comando para ver como o compilador traz para si essas informações da máquina.

Dessa forma, podemos intuir que é possível passar diferentes valores para essas variáveis durante o processo de compilação. Go inclusive nos adianta quais os possíveis valores para elas na [documentação](https://go.dev/src/go/build/syslist.go)

Por exemplo, fazendo `GOOS=windows GOARCH=amd64 go build .` instruímos o compilador a fazer um binário que rode especificamente em sistemas operacionais Windows com arquitetura de processamento AMD64.

Isso acaba se tornando uma mão na roda não só para quem está desenvolvendo, mas também para quem fará a implementação.

Intuitivamente, se pensarmos em fazer o deploy usando Docker escreveríamos o Dockerfile da seguinte maneira:

```dockerfile
FROM golang:latest

WORKDIR go/src/app

COPY . .

ENV CGO_ENABLED=0

ENV GOFLAGS="-ldflags=-s -w"

RUN ["go", "mod", "init", "hello-world"]

RUN ["go", "build", "."]

CMD ["./main"]
```

para criar a imagem com `docker buildx build -t go-golang .`:

![](https://cdn.hashnode.com/res/hashnode/image/upload/v1731102423630/40817a78-f3b4-48c0-adf0-2d026adf24c5.png)

No terminal, docker image ls

Só que, se compreendermos que para rodar o binário não precisamos do compilador em si, mas só do kernel linux, podemos utilizar de técnicas de construção de imagens em Docker para otimizar ainda mais os recursos gastos por nossa imagem.

Nesse caso, em específico, podemos reduzir em centenas de vezes o espaço ocupado pela imagem sem comprometer o binário usando apenas o multi-stage no nosso Dockerfile.

Em resumo, essa técnica nos permitirá construir nossa imagem de container em duas etapas:

1. Estágio de build, onde copiaremos os arquivos da máquina local para o container montado com uma imagem base`golang:latest` que servirá apenas para que compilemos o código-fonte;
    
2. Estágio de execução, quando trazemos o binário já compilado para uma imagem base linux (sem o Go instalado) e o executamos.
    

Veja como poderíamos fazer isso usando uma distribuição popular do linux como Ubuntu:

```dockerfile
FROM golang:1.22 as build

WORKDIR /go/src/app

COPY . .

ENV CGO_ENABLED=0

ENV GOFLAGS="-ldflags=-s -w"

RUN ["go", "mod", "init", "hello-world"]

RUN ["go", "build", "."]

FROM ubuntu

WORKDIR /app

COPY --from=build /go/src/app /app

CMD ["./main"]
```

Construindo essa imagem com `docker buildx build -t go-ubuntu .` já temos uma boa diferença no recurso utilizado. Uma imagem mais de 10 vezes menor :

![](https://cdn.hashnode.com/res/hashnode/image/upload/v1731102425644/ec3619e0-c6ec-4b3d-8dcc-0fdc101fb0bc.png)

No terminal, docker image ls

E seguindo nessa linha podemos comprimir ainda mais nossa imagem. Usando `alpine:latest`, uma imagem base muito conhecida por quem costuma reduzir o tamanho dos containers:

![](https://cdn.hashnode.com/res/hashnode/image/upload/v1731102427668/3036612c-c8d1-44c7-99a0-10b9860c9c24.png)

No terminal, docker image ls

Ou, se quisermos esticar ainda mais a corda, podemos usar `scratch`, que basicamente é uma “imagem” linux mínima, vazia, que contém nenhum binário, biblioteca ou qualquer outra coisa, essa “distro” é muito comum quando queremos rodar um único binário:

![](https://cdn.hashnode.com/res/hashnode/image/upload/v1731102428802/e40f53bc-d989-46ca-9648-0e1e9eb8365a.png)

No terminal, docker image ls

Dessa maneira, conseguimos reduzir ainda mais o espaço ocupado pela nossa imagem. Nesse caso, uma imagem quase 94 vezes menor! Uma redução absurda.

Relembrando, nosso Dockerfile está montado da seguinte maneira:

```dockerfile
FROM golang:1.22 as build

WORKDIR /go/src/app

COPY . .

ENV CGO_ENABLED=0

ENV GOFLAGS="-ldflags=-s -w"

RUN ["go", "mod", "init", "hello-world"]

RUN ["go", "build", "."]

FROM scratch

WORKDIR /app

COPY --from=build /go/src/app /app

CMD ["./main"]
```

Essa forma de escrever nossos containers levanta muitos outros assuntos que poderemos discorrer sobre no futuro, mas agora vale a pena ressaltar que como a imagem `scratch` é mínima, ou seja, não possui pacotes, suas vulnerabilidades serão mínimas também; nesse caso: zero.

Podemos fazer várias verificações dentro desse tema, mas aqui temos um demonstrativo usando o Docker Scout, que já vem pré-instalado com o próprio Docker, para checar as CVE’s (*Common Vulnerabilities and Exposures*) da nossa imagem:

![https://cdn.hashnode.com/res/hashnode/image/upload/v1731102430697/5b4f6500-af54-46e8-af92-0f09ed14f426.png?w=1600&h=840&fit=crop&crop=entropy&auto=compress,format&format=webp](https://cdn.hashnode.com/res/hashnode/image/upload/v1731102430697/5b4f6500-af54-46e8-af92-0f09ed14f426.png?w=1600&h=840&fit=crop&crop=entropy&auto=compress,format&format=webp)

No terminal, docker install para a imagem “go-scratch”

Até agora vimos só as vantagens de trabalhar dessa maneira e, obviamente, não são só rosas nessa área.

Apesar da imagem Scratch ser bem legal e gerar resultados impressionantes à primeira vista, ela pode nos gerar alguns problemas ou dificuldades bem peculiares.

Se precisarmos rodar em um usuário não root, teremos que configurar tudo manualmente; ou ainda, se precisarmos fazer chamadas https, precisaremos instalar todas as cadeias de certificado manualmente. Nesses casos, usar um Linux Alpine já se torna muito mais cômodo para a construção do container.

Esse é um assunto que provoca muitos debates. Cada assunto mencionado desencadeia ramificações extensas para discussão.

Aqui tratamos sobre Go, mas como ficaria o empacotamento de aplicações em linguagens que não geram binários, como Python, por exemplo?

E se não quisermos/pudermos usar o scratch, como podemos fazer para reduzir as vulnerabilidades da nossa imagem?

Que outras flags de vinculação (*linker flags*) podemos usar? Existem só essas? E as flags de compilação, o que são?

De toda forma, são duvidas que só poderemos sanar estudando, testando e trocando figurinhas com os outros da forma que fiz com vocês aqui!