MAKEFILE_THIS := $(lastword $(MAKEFILE_LIST))
SRC_PATH      := $(patsubst %/,%,$(dir $(abspath $(MAKEFILE_THIS))))
DEPLOY_PATH   := $(SRC_PATH)/../org1.example.com/gateway
LAB_PATH      ?= $(SRC_PATH)/../..
FAB_PATH      ?= $(LAB_PATH)/hyperledger/fabric-samples

.PHONY: all
all: build

.PHONY: build
build: codegen
	cd src && GOOS=darwin GOARCH=amd64 go build -o ../gateway-darwin
	cd src && GOOS=linux GOARCH=amd64 go build -o ../gateway-linux

.PHONY: dist
dist: gateway-linux
	rm -rf $(DEPLOY_PATH)/gateway
	cp gateway-linux $(DEPLOY_PATH)/gateway
	cp src/proto/fabric/fabric.proto $(DEPLOY_PATH)
	cp -Rf swagger-ui $(DEPLOY_PATH)

.PHONY: run
run:
	CRYPTO_PATH=$(FAB_PATH)/test-network/organizations ./gateway-darwin -logtostderr -v 2

.PHONY: codegen
codegen:
	protoc -I=./src/proto \
		--go_out ./src --go_opt paths=source_relative \
		--go-grpc_out ./src --go-grpc_opt paths=source_relative \
		./src/proto/fabric/fabric.proto
	protoc -I=./src/proto \
		--grpc-gateway_out ./src \
		--grpc-gateway_opt logtostderr=true \
		--grpc-gateway_opt paths=source_relative \
		./src/proto/fabric/fabric.proto
	protoc -I=./src/proto --openapiv2_out ./src \
		--openapiv2_opt logtostderr=true \
		./src/proto/fabric/fabric.proto
	-cp src/fabric/fabric.swagger.json swagger-ui

.PHONY: tools
tools:
	cd tools && go install \
		github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway \
		github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2 \
		google.golang.org/protobuf/cmd/protoc-gen-go \
		google.golang.org/grpc/cmd/protoc-gen-go-grpc
