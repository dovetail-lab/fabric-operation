module github.com/dovetail-lab/fabric-operation/service

go 1.14

replace honnef.co/go/tools => honnef.co/go/tools v0.0.1-2020.1.6

require (
	github.com/golang/glog v0.0.0-20160126235308-23def4e6c14b
	github.com/golang/protobuf v1.4.3
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.0.1
	github.com/hyperledger/fabric-sdk-go v1.0.0-beta3
	github.com/pkg/errors v0.9.1
	github.com/stretchr/testify v1.6.1
	google.golang.org/genproto v0.0.0-20201019141844-1ed22bb0c154
	google.golang.org/grpc v1.33.1
	google.golang.org/protobuf v1.25.0
)
