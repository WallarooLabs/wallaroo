package wallarooapi

import (
	"C"
	"unsafe"
)

type Encoder interface {
	Encode(d interface{}) []byte
}

//export EncoderEncode
func EncoderEncode(encoderId uint64, dataId uint64, size *uint64) unsafe.Pointer {
	encoder := GetComponent(encoderId).(Encoder)
	data := GetComponent(dataId)
	res := encoder.Encode(data)
	*size = uint64(len(res))
	return C.CBytes(res)
}
