unit uWebP;

{$mode objfpc}{$H+}
{$POINTERMATH ON}
{$R-}
{$Q-}
{$WARN 5057 OFF}   // local variables that are filled by FillChar / read from the stream
{$WARN 5091 OFF}
{$WARN 5025 OFF}

{ WebP pictures, decoded in plain Pascal (no external library): lossy (VP8), lossless (VP8L),
  transparency (ALPH chunk or lossless alpha) and the first frame of animated files. The lossy
  decoder follows libwebp's arithmetic exactly (including its "fancy" chroma upsampling), so the
  pixels are the same ones other programs show. Transparent pictures are shown on white.
  Not supported: lossy files that use inter-frame data (WebP never does) and ICC color
  conversion (the color profile is ignored). }

interface

uses
  Classes, SysUtils, Graphics, FPImage;

{ Builds a thumbnail with at most MaxSide pixels on its long side. False (with a reason in Err)
  when the file cannot be read. }
function LoadWebPThumb(const FileName: string; MaxSide: Integer; Bmp: TBitmap;
  out Err: string): Boolean;
{ The same picture as a memory image (for the viewer), long side at least Target where possible. }
function LoadWebPMemImage(const FileName: string; Target: Integer; out Err: string): TFPMemoryImage;

implementation

uses
  Math;

type
  EWebP = class(Exception);  // error raised for damaged or unsupported files
  TByteArr = array of Byte;  // array of bytes
  TPix = array of Cardinal;  // array of 32-bit pixels

const
  Coef0: array[0..1055] of Byte = (  // default coefficient probabilities of the VP8 format
    128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128,
    128, 128, 128, 128, 128, 128, 128, 128, 128, 253, 136, 254, 255, 228, 219, 128, 128, 128, 128, 128, 189, 129, 242, 255,
    227, 213, 255, 219, 128, 128, 128, 106, 126, 227, 252, 214, 209, 255, 255, 128, 128, 128, 1, 98, 248, 255, 236, 226,
    255, 255, 128, 128, 128, 181, 133, 238, 254, 221, 234, 255, 154, 128, 128, 128, 78, 134, 202, 247, 198, 180, 255, 219,
    128, 128, 128, 1, 185, 249, 255, 243, 255, 128, 128, 128, 128, 128, 184, 150, 247, 255, 236, 224, 128, 128, 128, 128,
    128, 77, 110, 216, 255, 236, 230, 128, 128, 128, 128, 128, 1, 101, 251, 255, 241, 255, 128, 128, 128, 128, 128, 170,
    139, 241, 252, 236, 209, 255, 255, 128, 128, 128, 37, 116, 196, 243, 228, 255, 255, 255, 128, 128, 128, 1, 204, 254,
    255, 245, 255, 128, 128, 128, 128, 128, 207, 160, 250, 255, 238, 128, 128, 128, 128, 128, 128, 102, 103, 231, 255, 211,
    171, 128, 128, 128, 128, 128, 1, 152, 252, 255, 240, 255, 128, 128, 128, 128, 128, 177, 135, 243, 255, 234, 225, 128,
    128, 128, 128, 128, 80, 129, 211, 255, 194, 224, 128, 128, 128, 128, 128, 1, 1, 255, 128, 128, 128, 128, 128, 128,
    128, 128, 246, 1, 255, 128, 128, 128, 128, 128, 128, 128, 128, 255, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128,
    198, 35, 237, 223, 193, 187, 162, 160, 145, 155, 62, 131, 45, 198, 221, 172, 176, 220, 157, 252, 221, 1, 68, 47,
    146, 208, 149, 167, 221, 162, 255, 223, 128, 1, 149, 241, 255, 221, 224, 255, 255, 128, 128, 128, 184, 141, 234, 253,
    222, 220, 255, 199, 128, 128, 128, 81, 99, 181, 242, 176, 190, 249, 202, 255, 255, 128, 1, 129, 232, 253, 214, 197,
    242, 196, 255, 255, 128, 99, 121, 210, 250, 201, 198, 255, 202, 128, 128, 128, 23, 91, 163, 242, 170, 187, 247, 210,
    255, 255, 128, 1, 200, 246, 255, 234, 255, 128, 128, 128, 128, 128, 109, 178, 241, 255, 231, 245, 255, 255, 128, 128,
    128, 44, 130, 201, 253, 205, 192, 255, 255, 128, 128, 128, 1, 132, 239, 251, 219, 209, 255, 165, 128, 128, 128, 94,
    136, 225, 251, 218, 190, 255, 255, 128, 128, 128, 22, 100, 174, 245, 186, 161, 255, 199, 128, 128, 128, 1, 182, 249,
    255, 232, 235, 128, 128, 128, 128, 128, 124, 143, 241, 255, 227, 234, 128, 128, 128, 128, 128, 35, 77, 181, 251, 193,
    211, 255, 205, 128, 128, 128, 1, 157, 247, 255, 236, 231, 255, 255, 128, 128, 128, 121, 141, 235, 255, 225, 227, 255,
    255, 128, 128, 128, 45, 99, 188, 251, 195, 217, 255, 224, 128, 128, 128, 1, 1, 251, 255, 213, 255, 128, 128, 128,
    128, 128, 203, 1, 248, 255, 255, 128, 128, 128, 128, 128, 128, 137, 1, 177, 255, 224, 255, 128, 128, 128, 128, 128,
    253, 9, 248, 251, 207, 208, 255, 192, 128, 128, 128, 175, 13, 224, 243, 193, 185, 249, 198, 255, 255, 128, 73, 17,
    171, 221, 161, 179, 236, 167, 255, 234, 128, 1, 95, 247, 253, 212, 183, 255, 255, 128, 128, 128, 239, 90, 244, 250,
    211, 209, 255, 255, 128, 128, 128, 155, 77, 195, 248, 188, 195, 255, 255, 128, 128, 128, 1, 24, 239, 251, 218, 219,
    255, 205, 128, 128, 128, 201, 51, 219, 255, 196, 186, 128, 128, 128, 128, 128, 69, 46, 190, 239, 201, 218, 255, 228,
    128, 128, 128, 1, 191, 251, 255, 255, 128, 128, 128, 128, 128, 128, 223, 165, 249, 255, 213, 255, 128, 128, 128, 128,
    128, 141, 124, 248, 255, 255, 128, 128, 128, 128, 128, 128, 1, 16, 248, 255, 255, 128, 128, 128, 128, 128, 128, 190,
    36, 230, 255, 236, 255, 128, 128, 128, 128, 128, 149, 1, 255, 128, 128, 128, 128, 128, 128, 128, 128, 1, 226, 255,
    128, 128, 128, 128, 128, 128, 128, 128, 247, 192, 255, 128, 128, 128, 128, 128, 128, 128, 128, 240, 128, 255, 128, 128,
    128, 128, 128, 128, 128, 128, 1, 134, 252, 255, 255, 128, 128, 128, 128, 128, 128, 213, 62, 250, 255, 255, 128, 128,
    128, 128, 128, 128, 55, 93, 255, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128,
    128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128,
    202, 24, 213, 235, 186, 191, 220, 160, 240, 175, 255, 126, 38, 182, 232, 169, 184, 228, 174, 255, 187, 128, 61, 46,
    138, 219, 151, 178, 240, 170, 255, 216, 128, 1, 112, 230, 250, 199, 191, 247, 159, 255, 255, 128, 166, 109, 228, 252,
    211, 215, 255, 174, 128, 128, 128, 39, 77, 162, 232, 172, 180, 245, 178, 255, 255, 128, 1, 52, 220, 246, 198, 199,
    249, 220, 255, 255, 128, 124, 74, 191, 243, 183, 193, 250, 221, 255, 255, 128, 24, 71, 130, 219, 154, 170, 243, 182,
    255, 255, 128, 1, 182, 225, 249, 219, 240, 255, 224, 128, 128, 128, 149, 150, 226, 252, 216, 205, 255, 171, 128, 128,
    128, 28, 108, 170, 242, 183, 194, 254, 223, 255, 255, 128, 1, 81, 230, 252, 204, 203, 255, 192, 128, 128, 128, 123,
    102, 209, 247, 188, 196, 255, 233, 128, 128, 128, 20, 95, 153, 243, 164, 173, 255, 203, 128, 128, 128, 1, 222, 248,
    255, 216, 213, 128, 128, 128, 128, 128, 168, 175, 246, 252, 235, 205, 255, 255, 128, 128, 128, 47, 116, 215, 255, 211,
    212, 255, 255, 128, 128, 128, 1, 121, 236, 253, 212, 214, 255, 255, 128, 128, 128, 141, 84, 213, 252, 201, 202, 255,
    219, 128, 128, 128, 42, 80, 160, 240, 162, 185, 255, 205, 128, 128, 128, 1, 1, 255, 128, 128, 128, 128, 128, 128,
    128, 128, 244, 1, 255, 128, 128, 128, 128, 128, 128, 128, 128, 238, 1, 255, 128, 128, 128, 128, 128, 128, 128, 128);
  UpdP: array[0..1055] of Byte = (  // probability updates for the coefficient probabilities
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 176, 246, 255, 255, 255, 255, 255, 255, 255, 255, 255, 223, 241, 252, 255,
    255, 255, 255, 255, 255, 255, 255, 249, 253, 253, 255, 255, 255, 255, 255, 255, 255, 255, 255, 244, 252, 255, 255, 255,
    255, 255, 255, 255, 255, 234, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255, 253, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 246, 254, 255, 255, 255, 255, 255, 255, 255, 255, 239, 253, 254, 255, 255, 255, 255, 255, 255, 255,
    255, 254, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 248, 254, 255, 255, 255, 255, 255, 255, 255, 255, 251,
    255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 253, 254,
    255, 255, 255, 255, 255, 255, 255, 255, 251, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255, 254, 255, 254, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 254, 253, 255, 254, 255, 255, 255, 255, 255, 255, 250, 255, 254, 255, 254, 255, 255,
    255, 255, 255, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    217, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 225, 252, 241, 253, 255, 255, 254, 255, 255, 255, 255, 234, 250,
    241, 250, 253, 255, 253, 254, 255, 255, 255, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 223, 254, 254, 255,
    255, 255, 255, 255, 255, 255, 255, 238, 253, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255, 248, 254, 255, 255, 255,
    255, 255, 255, 255, 255, 249, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 253, 255, 255, 255, 255, 255, 255, 255, 255, 255, 247, 254, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 253, 254, 255, 255, 255, 255, 255, 255, 255, 255, 252,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 254,
    255, 255, 255, 255, 255, 255, 255, 255, 253, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 254, 253, 255, 255, 255, 255, 255, 255, 255, 255, 250, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    186, 251, 250, 255, 255, 255, 255, 255, 255, 255, 255, 234, 251, 244, 254, 255, 255, 255, 255, 255, 255, 255, 251, 251,
    243, 253, 254, 255, 254, 255, 255, 255, 255, 255, 253, 254, 255, 255, 255, 255, 255, 255, 255, 255, 236, 253, 254, 255,
    255, 255, 255, 255, 255, 255, 255, 251, 253, 253, 254, 254, 255, 255, 255, 255, 255, 255, 255, 254, 254, 255, 255, 255,
    255, 255, 255, 255, 255, 254, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 254, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    248, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 250, 254, 252, 254, 255, 255, 255, 255, 255, 255, 255, 248, 254,
    249, 253, 255, 255, 255, 255, 255, 255, 255, 255, 253, 253, 255, 255, 255, 255, 255, 255, 255, 255, 246, 253, 253, 255,
    255, 255, 255, 255, 255, 255, 255, 252, 254, 251, 254, 254, 255, 255, 255, 255, 255, 255, 255, 254, 252, 255, 255, 255,
    255, 255, 255, 255, 255, 248, 254, 253, 255, 255, 255, 255, 255, 255, 255, 255, 253, 255, 254, 254, 255, 255, 255, 255,
    255, 255, 255, 255, 251, 254, 255, 255, 255, 255, 255, 255, 255, 255, 245, 251, 254, 255, 255, 255, 255, 255, 255, 255,
    255, 253, 253, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 251, 253, 255, 255, 255, 255, 255, 255, 255, 255, 252,
    253, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 252, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 249, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 254, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 253, 255, 255, 255, 255, 255, 255, 255, 255, 250, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 254, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255);
  BModes: array[0..899] of Byte = (  // probabilities of the 4x4 intra modes
    231, 120, 48, 89, 115, 113, 120, 152, 112, 152, 179, 64, 126, 170, 118, 46, 70, 95, 175, 69, 143, 80, 85, 82,
    72, 155, 103, 56, 58, 10, 171, 218, 189, 17, 13, 152, 114, 26, 17, 163, 44, 195, 21, 10, 173, 121, 24, 80,
    195, 26, 62, 44, 64, 85, 144, 71, 10, 38, 171, 213, 144, 34, 26, 170, 46, 55, 19, 136, 160, 33, 206, 71,
    63, 20, 8, 114, 114, 208, 12, 9, 226, 81, 40, 11, 96, 182, 84, 29, 16, 36, 134, 183, 89, 137, 98, 101,
    106, 165, 148, 72, 187, 100, 130, 157, 111, 32, 75, 80, 66, 102, 167, 99, 74, 62, 40, 234, 128, 41, 53, 9,
    178, 241, 141, 26, 8, 107, 74, 43, 26, 146, 73, 166, 49, 23, 157, 65, 38, 105, 160, 51, 52, 31, 115, 128,
    104, 79, 12, 27, 217, 255, 87, 17, 7, 87, 68, 71, 44, 114, 51, 15, 186, 23, 47, 41, 14, 110, 182, 183,
    21, 17, 194, 66, 45, 25, 102, 197, 189, 23, 18, 22, 88, 88, 147, 150, 42, 46, 45, 196, 205, 43, 97, 183,
    117, 85, 38, 35, 179, 61, 39, 53, 200, 87, 26, 21, 43, 232, 171, 56, 34, 51, 104, 114, 102, 29, 93, 77,
    39, 28, 85, 171, 58, 165, 90, 98, 64, 34, 22, 116, 206, 23, 34, 43, 166, 73, 107, 54, 32, 26, 51, 1,
    81, 43, 31, 68, 25, 106, 22, 64, 171, 36, 225, 114, 34, 19, 21, 102, 132, 188, 16, 76, 124, 62, 18, 78,
    95, 85, 57, 50, 48, 51, 193, 101, 35, 159, 215, 111, 89, 46, 111, 60, 148, 31, 172, 219, 228, 21, 18, 111,
    112, 113, 77, 85, 179, 255, 38, 120, 114, 40, 42, 1, 196, 245, 209, 10, 25, 109, 88, 43, 29, 140, 166, 213,
    37, 43, 154, 61, 63, 30, 155, 67, 45, 68, 1, 209, 100, 80, 8, 43, 154, 1, 51, 26, 71, 142, 78, 78,
    16, 255, 128, 34, 197, 171, 41, 40, 5, 102, 211, 183, 4, 1, 221, 51, 50, 17, 168, 209, 192, 23, 25, 82,
    138, 31, 36, 171, 27, 166, 38, 44, 229, 67, 87, 58, 169, 82, 115, 26, 59, 179, 63, 59, 90, 180, 59, 166,
    93, 73, 154, 40, 40, 21, 116, 143, 209, 34, 39, 175, 47, 15, 16, 183, 34, 223, 49, 45, 183, 46, 17, 33,
    183, 6, 98, 15, 32, 183, 57, 46, 22, 24, 128, 1, 54, 17, 37, 65, 32, 73, 115, 28, 128, 23, 128, 205,
    40, 3, 9, 115, 51, 192, 18, 6, 223, 87, 37, 9, 115, 59, 77, 64, 21, 47, 104, 55, 44, 218, 9, 54,
    53, 130, 226, 64, 90, 70, 205, 40, 41, 23, 26, 57, 54, 57, 112, 184, 5, 41, 38, 166, 213, 30, 34, 26,
    133, 152, 116, 10, 32, 134, 39, 19, 53, 221, 26, 114, 32, 73, 255, 31, 9, 65, 234, 2, 15, 1, 118, 73,
    75, 32, 12, 51, 192, 255, 160, 43, 51, 88, 31, 35, 67, 102, 85, 55, 186, 85, 56, 21, 23, 111, 59, 205,
    45, 37, 192, 55, 38, 70, 124, 73, 102, 1, 34, 98, 125, 98, 42, 88, 104, 85, 117, 175, 82, 95, 84, 53,
    89, 128, 100, 113, 101, 45, 75, 79, 123, 47, 51, 128, 81, 171, 1, 57, 17, 5, 71, 102, 57, 53, 41, 49,
    38, 33, 13, 121, 57, 73, 26, 1, 85, 41, 10, 67, 138, 77, 110, 90, 47, 114, 115, 21, 2, 10, 102, 255,
    166, 23, 6, 101, 29, 16, 10, 85, 128, 101, 196, 26, 57, 18, 10, 102, 102, 213, 34, 20, 43, 117, 20, 15,
    36, 163, 128, 68, 1, 26, 102, 61, 71, 37, 34, 53, 31, 243, 192, 69, 60, 71, 38, 73, 119, 28, 222, 37,
    68, 45, 128, 34, 1, 47, 11, 245, 171, 62, 17, 19, 70, 146, 85, 55, 62, 70, 37, 43, 37, 154, 100, 163,
    85, 160, 1, 63, 9, 92, 136, 28, 64, 32, 201, 85, 75, 15, 9, 9, 64, 255, 184, 119, 16, 86, 6, 28,
    5, 64, 255, 25, 248, 1, 56, 8, 17, 132, 137, 255, 55, 116, 128, 58, 15, 20, 82, 135, 57, 26, 121, 40,
    164, 50, 31, 137, 154, 133, 25, 35, 218, 51, 103, 44, 131, 131, 123, 31, 6, 158, 86, 40, 64, 135, 148, 224,
    45, 183, 128, 22, 26, 17, 131, 240, 154, 14, 1, 209, 45, 16, 21, 91, 64, 222, 7, 1, 197, 56, 21, 39,
    155, 60, 138, 23, 102, 213, 83, 12, 13, 54, 192, 255, 68, 47, 28, 85, 26, 85, 85, 128, 128, 32, 146, 171,
    18, 11, 7, 63, 144, 171, 4, 4, 246, 35, 27, 10, 146, 174, 171, 12, 26, 128, 190, 80, 35, 99, 180, 80,
    126, 54, 45, 85, 126, 47, 87, 176, 51, 41, 20, 32, 101, 75, 128, 139, 118, 146, 116, 128, 85, 56, 41, 15,
    176, 236, 85, 37, 9, 62, 71, 30, 17, 119, 118, 255, 17, 18, 138, 101, 38, 60, 138, 55, 70, 43, 26, 142,
    146, 36, 19, 30, 171, 255, 97, 27, 20, 138, 45, 61, 62, 219, 1, 81, 188, 64, 32, 41, 20, 117, 151, 142,
    20, 21, 163, 112, 19, 12, 61, 195, 128, 48, 4, 24);
  DcTab: array[0..127] of Word = (  // quantizer step sizes for DC coefficients
    4, 5, 6, 7, 8, 9, 10, 10, 11, 12, 13, 14, 15, 16, 17, 17,
    18, 19, 20, 20, 21, 21, 22, 22, 23, 23, 24, 25, 25, 26, 27, 28,
    29, 30, 31, 32, 33, 34, 35, 36, 37, 37, 38, 39, 40, 41, 42, 43,
    44, 45, 46, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58,
    59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74,
    75, 76, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89,
    91, 93, 95, 96, 98, 100, 101, 102, 104, 106, 108, 110, 112, 114, 116, 118,
    122, 124, 126, 128, 130, 132, 134, 136, 138, 140, 143, 145, 148, 151, 154, 157);
  AcTab: array[0..127] of Word = (  // quantizer step sizes for AC coefficients
    4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35,
    36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51,
    52, 53, 54, 55, 56, 57, 58, 60, 62, 64, 66, 68, 70, 72, 74, 76,
    78, 80, 82, 84, 86, 88, 90, 92, 94, 96, 98, 100, 102, 104, 106, 108,
    110, 112, 114, 116, 119, 122, 125, 128, 131, 134, 137, 140, 143, 146, 149, 152,
    155, 158, 161, 164, 167, 170, 173, 177, 181, 185, 189, 193, 197, 201, 205, 209,
    213, 217, 221, 225, 229, 234, 239, 245, 249, 254, 259, 264, 269, 274, 279, 284);
  PlaneTab: array[0..119] of Byte = (  // order of the coefficient planes
    24, 7, 23, 25, 40, 6, 39, 41, 22, 26, 38, 42, 56, 5, 55, 57, 21, 27, 54, 58, 37, 43, 72, 4,
    71, 73, 20, 28, 53, 59, 70, 74, 36, 44, 88, 69, 75, 52, 60, 3, 87, 89, 19, 29, 86, 90, 35, 45,
    68, 76, 85, 91, 51, 61, 104, 2, 103, 105, 18, 30, 102, 106, 34, 46, 84, 92, 67, 77, 101, 107, 50, 62,
    120, 1, 119, 121, 83, 93, 17, 31, 100, 108, 66, 78, 118, 122, 33, 47, 117, 123, 49, 63, 99, 109, 82, 94,
    0, 116, 124, 65, 79, 16, 32, 98, 110, 48, 115, 125, 81, 95, 64, 114, 126, 97, 111, 80, 113, 127, 96, 112);

  ZigZag: array[0..15] of Byte = (0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15);  // zigzag order of the 16 coefficients
  Bands: array[0..16] of Byte = (0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0);  // coefficient band of each position
  CatLen: array[0..3] of Integer = (3, 4, 5, 11);  // number of extra bits of the large value categories
  CatProb: array[0..3, 0..10] of Byte = (  // probabilities of the extra bits
    (173, 148, 140, 0, 0, 0, 0, 0, 0, 0, 0),
    (176, 155, 140, 135, 0, 0, 0, 0, 0, 0, 0),
    (180, 157, 141, 134, 130, 0, 0, 0, 0, 0, 0),
    (254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129));

  BDC = 0;  // DC prediction
  BTM = 1;  // TrueMotion prediction
  BVE = 2;  // vertical prediction
  BHE = 3;  // horizontal prediction
  BRD = 4;  // down-right prediction
  BVR = 5;  // vertical-right prediction
  BLD = 6;  // left-down prediction
  BVL = 7;  // vertical-left prediction
  BHD = 8;  // horizontal-down prediction
  BHU = 9;  // horizontal-up prediction

  { intra 4x4 mode tree: values <= 0 are leaves (minus the mode), values > 0 are the next node }
  YModes4: array[0..17] of ShortInt = (-BDC, 1, -BTM, 2, -BVE, 3, 4, 6, -BHE, 5, -BRD, -BVR,
    -BLD, 7, -BVL, 8, -BHD, -BHU);

{ Raises a WebP error with the given message. }
procedure Bad(const Msg: string);
begin
  raise EWebP.Create(Msg);
end;

{ Arithmetic shift right (FPC shr on a negative number is a logical shift). }
{ arithmetic shift right (FPC's shr on a negative number is a logical shift) }
function Sar(V, N: Integer): Integer; inline;
begin
  if V >= 0 then Result := V shr N else Result := not ((not V) shr N);
end;

{ Arithmetic shift right for 64-bit values. }
function SarL(V: Int64; N: Integer): Int64; inline;
begin
  if V >= 0 then Result := V shr N else Result := not ((not V) shr N);
end;

{ Limits a value to 0..255. }
function Clip255(V: Integer): Integer; inline;
begin
  if V < 0 then Result := 0 else if V > 255 then Result := 255 else Result := V;
end;

{ ---- boolean entropy decoder (VP8) ---- }

type
  { State of the VP8 boolean entropy decoder. }
  TBoolDec = record
    B: PByte;  // data buffer
    P, E: PtrInt;  // P: read position; E: end position
    Value: Cardinal;  // current value
    Rng: Integer;  // current range
    Cnt: Integer;  // bits shifted since the last byte was loaded
  end;

{ Returns the next byte of the data, or 0 past the end. }
function BNext(var R: TBoolDec): Integer; inline;
begin
  if R.P < R.E then Result := R.B[R.P] else Result := 0;  // byte or zero past the end
  Inc(R.P);  // move the position
end;

{ Starts the boolean decoder on a data block. }
procedure BInit(var R: TBoolDec; B: PByte; Start, Size: PtrInt);
begin
  R.B := B;  // data buffer
  R.P := Start;  // start position
  R.E := Start + Size;  // end position
  R.Rng := 255;  // initial range
  R.Cnt := 0;  // no bits shifted yet
  R.Value := Cardinal(BNext(R)) shl 8;  // load the first byte
  R.Value := R.Value or Cardinal(BNext(R));  // load the second byte
end;

{ Decodes one boolean with the given probability. }
function BGet(var R: TBoolDec; Prob: Integer): Integer;
var
  Split, SS: Cardinal;  // Split: range split point; SS: split point scaled to the value
begin
  Split := 1 + (((Cardinal(R.Rng) - 1) * Cardinal(Prob)) shr 8);  // split point of the range
  SS := Split shl 8;  // scaled split point
  if R.Value >= SS then  // value is in the upper part
  begin
    Result := 1;  // bit is one
    R.Rng := R.Rng - Integer(Split);  // upper range
    R.Value := R.Value - SS;  // remove the lower part
  end
  else
  begin
    Result := 0;  // bit is zero
    R.Rng := Integer(Split);  // lower range
  end;
  while R.Rng < 128 do  // renormalize the range
  begin
    R.Value := R.Value shl 1;  // shift the value
    R.Rng := R.Rng shl 1;  // double the range
    Inc(R.Cnt);  // count the shifted bit
    if R.Cnt = 8 then  // a byte has been shifted out
    begin
      R.Cnt := 0;  // restart the count
      R.Value := R.Value or Cardinal(BNext(R));  // load the next byte
    end;
  end;
end;

{ Reads an N-bit unsigned value, most significant bit first. }
function BValue(var R: TBoolDec; N: Integer): Integer;
var
  V: Integer;  // V: value
begin
  V := 0;  // start at zero
  while N > 0 do  // for each bit
  begin
    Dec(N);  // next bit position
    V := V or (BGet(R, $80) shl N);  // add the bit
  end;
  Result := V;  // return the value
end;

{ Reads an N-bit value followed by a sign bit. }
function BSigned(var R: TBoolDec; N: Integer): Integer;
begin
  Result := BValue(R, N);  // read the magnitude
  if BGet(R, $80) <> 0 then Result := -Result;  // apply the sign
end;

{ ---- VP8 (lossy) ---- }

type
  { Coefficients of one 4x4 block. }
  TBlk = array[0..15] of Integer;
  TCoefs = array[0..23] of TBlk;  // coefficients of the 24 blocks of a macroblock
  TWork = array[0..32 * 17 - 1] of Byte;  // working area of 32 columns for prediction and reconstruction
  TProbT = array[0..7, 0..2, 0..10] of Byte;  // coefficient probabilities of one block type
  TProbs = array[0..3] of TProbT;  // probabilities of the four block types
  TFInfo = record  // loop filter values of one macroblock
    Limit, ILevel, Hev, Inner: Integer;  // Limit: edge limit; ILevel: interior limit; Hev: high edge variance threshold; Inner: inner edges are filtered
  end;
  TFrame = record  // decoded picture
    W, H, Cw, MbW, MbH: Integer;     // W, H: padded to whole macroblocks
    Y, U, V: TByteArr;  // luma and chroma planes
  end;

{ Reads a coefficient larger than one. }
function GetLarge(var BR: TBoolDec; P: PByte): Integer;
var
  V, Bit1, Bit0, Cat, I: Integer;  // V: value; Bit1, Bit0: category bits; Cat: category; I: loop counter
begin
  if BGet(BR, P[3]) = 0 then  // small values
  begin
    if BGet(BR, P[4]) = 0 then  // value 2, or 3 and 4
      V := 2  // value 2
    else
      V := 3 + BGet(BR, P[5]);  // value 3 or 4
  end
  else if BGet(BR, P[6]) = 0 then  // values 5 to 10
  begin
    if BGet(BR, P[7]) = 0 then  // value 5 or 6
      V := 5 + BGet(BR, 159)  // value 5 or 6
    else
    begin
      V := 7 + 2 * BGet(BR, 165);  // value 7 to 10
      V := V + BGet(BR, 145);  // value 7 to 10
    end;
  end
  else
  begin
    Bit1 := BGet(BR, P[8]);  // category bit 1
    Bit0 := BGet(BR, P[9 + Bit1]);  // category bit 0
    Cat := 2 * Bit1 + Bit0;  // category number
    V := 0;  // start at zero
    for I := 0 to CatLen[Cat] - 1 do  // extra bits of the category
      V := V + V + BGet(BR, CatProb[Cat, I]);  // add the next bit
    V := V + 3 + (8 shl Cat);  // add the base value of the category
  end;
  Result := V;  // return the value
end;

{ Reads the coefficients of one block and returns the index after the last one. }
function GetCoeffs(var BR: TBoolDec; const Prob: TProbT; Ctx: Integer; DQ0, DQ1: Integer;
  N: Integer; var Outp: TBlk): Integer;
var
  P: PByte;  // P: probabilities of the current position
  V, NextCtx: Integer;  // V: value; NextCtx: context of the next position
begin
  P := PByte(@Prob[Bands[N], Ctx, 0]);  // probabilities of the first position
  while N < 16 do  // until the block is full
  begin
    if BGet(BR, P[0]) = 0 then  // end of block
    begin
      Result := N;  // return the position
      Exit;  // done
    end;
    while BGet(BR, P[1]) = 0 do  // skip zero coefficients
    begin
      Inc(N);  // next position
      P := PByte(@Prob[Bands[N], 0, 0]);  // probabilities of the new position
      if N = 16 then  // end of the block
      begin
        Result := 16;  // return 16
        Exit;  // done
      end;
    end;
    if BGet(BR, P[2]) = 0 then  // value is one
    begin
      V := 1;  // value one
      NextCtx := 1;  // next context is 1
    end
    else
    begin
      V := GetLarge(BR, P);  // large value
      NextCtx := 2;  // next context is 2
    end;
    if BGet(BR, $80) <> 0 then V := -V;  // apply the sign
    if N > 0 then Outp[ZigZag[N]] := V * DQ1 else Outp[ZigZag[N]] := V * DQ0;  // dequantize and store in raster order
    Inc(N);  // next position
    P := PByte(@Prob[Bands[N], NextCtx, 0]);  // probabilities of the next position
  end;
  Result := 16;  // all positions used
end;

{ First multiplier of the inverse transform (about 1.306). }
function Mul1(A: Integer): Integer; inline;
begin
  Result := Integer(SarL(Int64(A) * 20091, 16)) + A;  // multiply and add the value
end;

{ Second multiplier of the inverse transform (about 0.541). }
function Mul2(A: Integer): Integer; inline;
begin
  Result := Integer(SarL(Int64(A) * 35468, 16));  // multiply
end;

{ inverse DCT of one 4x4 block, added to the prediction at Buf[Pos] }
procedure IdctAdd(const C: TBlk; var Buf: TWork; Pos: Integer);
var
  Tmp: array[0..15] of Integer;  // Tmp: intermediate values
  I, A, B, Cc, D, Dc, O: Integer;  // I: loop counter; A, B, Cc, D: butterfly values; Dc: rounded DC; O: offset of the row
begin
  for I := 0 to 3 do  // vertical pass
  begin
    A := C[0 + I] + C[8 + I];  // sum of the even inputs
    B := C[0 + I] - C[8 + I];  // difference of the even inputs
    Cc := Mul2(C[4 + I]) - Mul1(C[12 + I]);  // odd part
    D := Mul1(C[4 + I]) + Mul2(C[12 + I]);  // odd part
    Tmp[4 * I + 0] := A + D;  // output 0
    Tmp[4 * I + 1] := B + Cc;  // output 1
    Tmp[4 * I + 2] := B - Cc;  // output 2
    Tmp[4 * I + 3] := A - D;  // output 3
  end;
  for I := 0 to 3 do  // horizontal pass
  begin
    Dc := Tmp[0 + I] + 4;  // DC with rounding
    A := Dc + Tmp[8 + I];  // sum of the even inputs
    B := Dc - Tmp[8 + I];  // difference of the even inputs
    Cc := Mul2(Tmp[4 + I]) - Mul1(Tmp[12 + I]);  // odd part
    D := Mul1(Tmp[4 + I]) + Mul2(Tmp[12 + I]);  // odd part
    O := Pos + I * 32;  // offset of the row
    Buf[O + 0] := Byte(Clip255(Buf[O + 0] + Sar(A + D, 3)));  // add to the prediction
    Buf[O + 1] := Byte(Clip255(Buf[O + 1] + Sar(B + Cc, 3)));  // add to the prediction
    Buf[O + 2] := Byte(Clip255(Buf[O + 2] + Sar(B - Cc, 3)));  // add to the prediction
    Buf[O + 3] := Byte(Clip255(Buf[O + 3] + Sar(A - D, 3)));  // add to the prediction
  end;
end;

{ True when any coefficient of the block is not zero. }
function BlkNonZero(const C: TBlk): Boolean;
var
  I: Integer;  // I: loop counter
begin
  Result := True;  // assume not zero
  for I := 0 to 15 do  // every coefficient
    if C[I] <> 0 then Exit;  // found one
  Result := False;  // all zero
end;

{ Returns the index of pixel (R, C) in the working area. }
function WI(R, C: Integer): Integer; inline;
begin
  Result := (R + 1) * 32 + C + 1;  // row and column with a one pixel border
end;

{ Returns the weighted average of three pixels. }
function Avg3(A, B, C: Integer): Integer; inline;
begin
  Result := (A + 2 * B + C + 2) shr 2;  // (A + 2B + C) / 4 with rounding
end;

{ Returns the average of two pixels. }
function Avg2i(A, B: Integer): Integer; inline;
begin
  Result := (A + B + 1) shr 1;  // (A + B) / 2 with rounding
end;

{ 16x16 luma or 8x8 chroma prediction }
procedure Pred16(var Buf: TWork; Size, Mode, MbX, MbY: Integer);
var
  R, C, S, Dc, Sh, Tl: Integer;  // R, C: row and column; S: sum; Dc: DC value; Sh: shift; Tl: top-left pixel
begin
  case Mode of  // by mode
    BDC:  // DC prediction
      begin
        if Size = 16 then Sh := 4 else Sh := 3;  // shift for the pixel count
        if (MbX = 0) and (MbY = 0) then  // no neighbors
          Dc := $80  // neutral gray
        else if MbX = 0 then  // only the top row is missing
        begin
          S := 0;  // sum of the left pixels
          for C := 0 to Size - 1 do S := S + Buf[WI(-1, C)];  // add the left column
          Dc := (S + (Size shr 1)) shr Sh;  // average with rounding
        end  // only the left column is missing
        else if MbY = 0 then
        begin  // sum of the top pixels
          S := 0;  // add the top row
          for R := 0 to Size - 1 do S := S + Buf[WI(R, -1)];  // average with rounding
          Dc := (S + (Size shr 1)) shr Sh;
        end
        else  // both neighbors exist
        begin
          S := 0;  // sum of all neighbors
          for C := 0 to Size - 1 do S := S + Buf[WI(-1, C)];  // add the top row
          for R := 0 to Size - 1 do S := S + Buf[WI(R, -1)];  // add the left column
          Dc := (S + Size) shr (Sh + 1);  // average with rounding
        end;
        for R := 0 to Size - 1 do  // fill the block
          for C := 0 to Size - 1 do Buf[WI(R, C)] := Byte(Dc);  // fill the row
      end;
    BTM:  // TrueMotion prediction
      begin
        Tl := Buf[WI(-1, -1)];  // top-left pixel
        for R := 0 to Size - 1 do  // every row
          for C := 0 to Size - 1 do  // every column
            Buf[WI(R, C)] := Byte(Clip255(Buf[WI(-1, C)] + Buf[WI(R, -1)] - Tl));  // left + top - top-left
      end;
    BVE:  // vertical prediction
      for R := 0 to Size - 1 do  // every row
        for C := 0 to Size - 1 do Buf[WI(R, C)] := Buf[WI(-1, C)];  // copy the row above
  else  // horizontal prediction
    for R := 0 to Size - 1 do  // every row
      for C := 0 to Size - 1 do Buf[WI(R, C)] := Buf[WI(R, -1)];  // copy the pixel on the left
  end;
end;

{ 4x4 luma prediction; Pos is the index of the block's top-left pixel in Buf }
procedure Pred4(var Buf: TWork; Pos, Mode: Integer);
var
  X, A, B, C, D, E, F, G, H, I, J, K, L, V, Y, Dc: Integer;  // X: corner pixel; A..H: pixels above and to the right; I..L: pixels on the left; V, Y, Dc: work values
  Vals: array[0..3] of Integer;  // Vals: four predicted values

  { Returns the pixel at (PX, PY) relative to the block. }
  function P(PX, PY: Integer): Integer;
  begin
    Result := Buf[Pos + PY * 32 + PX];  // read from the working area
  end;

  { Stores the value SV at (SX, SY) relative to the block. }
  procedure S(SX, SY, SV: Integer);
  begin
    Buf[Pos + SY * 32 + SX] := Byte(SV);  // write to the working area
  end;

begin
  X := P(-1, -1);  // corner pixel
  A := P(0, -1); B := P(1, -1); C := P(2, -1); D := P(3, -1);  // top row, first four pixels
  E := P(4, -1); F := P(5, -1); G := P(6, -1); H := P(7, -1);  // top row, next four pixels
  I := P(-1, 0); J := P(-1, 1); K := P(-1, 2); L := P(-1, 3);  // left column
  case Mode of  // by mode
    BDC:  // DC prediction
      begin
        Dc := 4;  // rounding
        for V := 0 to 3 do Dc := Dc + P(V, -1) + P(-1, V);  // add the top row and the left column
        Dc := Dc shr 3;  // average
        for Y := 0 to 3 do  // every row
          for V := 0 to 3 do S(V, Y, Dc);  // fill the row
      end;
    BTM:  // TrueMotion prediction
      for Y := 0 to 3 do  // every row
        for V := 0 to 3 do S(V, Y, Clip255(P(V, -1) + P(-1, Y) - X));  // left + top - corner
    BVE:  // vertical prediction
      begin
        Vals[0] := Avg3(X, A, B);  // smoothed top pixel 0
        Vals[1] := Avg3(A, B, C);  // smoothed top pixel 1
        Vals[2] := Avg3(B, C, D);  // smoothed top pixel 2
        Vals[3] := Avg3(C, D, E);  // smoothed top pixel 3
        for Y := 0 to 3 do  // every row
          for V := 0 to 3 do S(V, Y, Vals[V]);  // copy the top values
      end;
    BHE:  // horizontal prediction
      begin
        Vals[0] := Avg3(X, I, J);  // smoothed left pixel 0
        Vals[1] := Avg3(I, J, K);  // smoothed left pixel 1
        Vals[2] := Avg3(J, K, L);  // smoothed left pixel 2
        Vals[3] := Avg3(K, L, L);  // smoothed left pixel 3
        for Y := 0 to 3 do  // every column
          for V := 0 to 3 do S(V, Y, Vals[Y]);  // copy the left values
      end;
    BRD:  // down-right prediction
      begin
        S(0, 3, Avg3(J, K, L));  // bottom left pixel
        V := Avg3(I, J, K); S(1, 3, V); S(0, 2, V);  // diagonal values
        V := Avg3(X, I, J); S(2, 3, V); S(1, 2, V); S(0, 1, V);  // diagonal values
        V := Avg3(A, X, I); S(3, 3, V); S(2, 2, V); S(1, 1, V); S(0, 0, V);  // main diagonal
        V := Avg3(B, A, X); S(3, 2, V); S(2, 1, V); S(1, 0, V);  // diagonal values
        V := Avg3(C, B, A); S(3, 1, V); S(2, 0, V);  // diagonal values
        S(3, 0, Avg3(D, C, B));  // top right pixel
      end;
    BVR:  // vertical-right prediction
      begin
        V := Avg2i(X, A); S(0, 0, V); S(1, 2, V);  // first column of pairs
        V := Avg2i(A, B); S(1, 0, V); S(2, 2, V);  // second column of pairs
        V := Avg2i(B, C); S(2, 0, V); S(3, 2, V);  // third column of pairs
        S(3, 0, Avg2i(C, D));  // top right pixel
        S(0, 3, Avg3(K, J, I));  // bottom left pixel
        S(0, 2, Avg3(J, I, X));  // left pixel of the third row
        V := Avg3(I, X, A); S(0, 1, V); S(1, 3, V);  // diagonal values
        V := Avg3(X, A, B); S(1, 1, V); S(2, 3, V);  // diagonal values
        V := Avg3(A, B, C); S(2, 1, V); S(3, 3, V);  // diagonal values
        S(3, 1, Avg3(B, C, D));  // right pixel of the second row
      end;
    BLD:  // left-down prediction
      begin
        S(0, 0, Avg3(A, B, C));  // top left pixel
        V := Avg3(B, C, D); S(1, 0, V); S(0, 1, V);  // diagonal values
        V := Avg3(C, D, E); S(2, 0, V); S(1, 1, V); S(0, 2, V);  // diagonal values
        V := Avg3(D, E, F); S(3, 0, V); S(2, 1, V); S(1, 2, V); S(0, 3, V);  // main anti-diagonal
        V := Avg3(E, F, G); S(3, 1, V); S(2, 2, V); S(1, 3, V);  // diagonal values
        V := Avg3(F, G, H); S(3, 2, V); S(2, 3, V);  // diagonal values
        S(3, 3, Avg3(G, H, H));  // bottom right pixel
      end;
    BVL:  // vertical-left prediction
      begin
        S(0, 0, Avg2i(A, B));  // top left pixel
        V := Avg2i(B, C); S(1, 0, V); S(0, 2, V);  // pairs
        V := Avg2i(C, D); S(2, 0, V); S(1, 2, V);  // pairs
        V := Avg2i(D, E); S(3, 0, V); S(2, 2, V);  // pairs
        S(0, 1, Avg3(A, B, C));  // second row start
        V := Avg3(B, C, D); S(1, 1, V); S(0, 3, V);  // second row values
        V := Avg3(C, D, E); S(2, 1, V); S(1, 3, V);  // second row values
        V := Avg3(D, E, F); S(3, 1, V); S(2, 3, V);  // second row values
        S(3, 2, Avg3(E, F, G));  // third row end
        S(3, 3, Avg3(F, G, H));  // bottom right pixel
      end;
    BHU:  // horizontal-up prediction
      begin
        S(0, 0, Avg2i(I, J));  // top left pixel
        V := Avg2i(J, K); S(2, 0, V); S(0, 1, V);  // pairs
        V := Avg2i(K, L); S(2, 1, V); S(0, 2, V);  // pairs
        S(1, 0, Avg3(I, J, K));  // second pixel of the first row
        V := Avg3(J, K, L); S(3, 0, V); S(1, 1, V);  // values
        V := Avg3(K, L, L); S(3, 1, V); S(1, 2, V);  // values
        S(3, 2, L); S(2, 2, L); S(0, 3, L); S(1, 3, L); S(2, 3, L); S(3, 3, L);  // bottom right pixels repeat the last left pixel
      end;
    BHD:  // horizontal-down prediction
      begin
        V := Avg2i(I, X); S(0, 0, V); S(2, 1, V);  // pairs
        V := Avg2i(J, I); S(0, 1, V); S(2, 2, V);  // pairs
        V := Avg2i(K, J); S(0, 2, V); S(2, 3, V);  // pairs
        S(0, 3, Avg2i(L, K));  // bottom left pixel
        S(3, 0, Avg3(A, B, C));  // top right pixel
        S(2, 0, Avg3(X, A, B));  // top row values
        V := Avg3(I, X, A); S(1, 0, V); S(3, 1, V);  // diagonal values
        V := Avg3(J, I, X); S(1, 1, V); S(3, 2, V);  // diagonal values
        V := Avg3(K, J, I); S(1, 2, V); S(3, 3, V);  // diagonal values
        S(1, 3, Avg3(L, K, J));  // bottom row values
      end;
  end;
end;

{ Predicts and reconstructs one macroblock into the frame. }
procedure Reconstruct(var F: TFrame; MbX, MbY: Integer; IsI4: Boolean; const IModes: TBlk;
  UVMode: Integer; var Co: TCoefs);
var
  Yb: TWork;  // Yb: luma working area
  Ub: TWork;  // Ub: chroma working area
  X0, Y0, Cx0, Cy0, R, C, N, Bx, By, Ch, K: Integer;  // X0, Y0: luma origin; Cx0, Cy0: chroma origin; R, C: row and column; N: block number; Bx, By: block position; Ch: chroma plane; K: loop counter
begin
  X0 := MbX * 16;  // luma x of the macroblock
  Y0 := MbY * 16;  // luma y of the macroblock
  FillChar(Yb, SizeOf(Yb), 0);  // clear the working area
  // top row, with 4 extra pixels to the right
  if MbY > 0 then  // top row exists
  begin
    for C := 0 to 15 do Yb[WI(-1, C)] := F.Y[(Y0 - 1) * F.W + X0 + C];  // copy the pixels above
    if MbX < F.MbW - 1 then  // not the last macroblock in the row
      for C := 16 to 19 do Yb[WI(-1, C)] := F.Y[(Y0 - 1) * F.W + X0 + C]  // copy the pixels above and to the right
    else
      for C := 16 to 19 do Yb[WI(-1, C)] := F.Y[(Y0 - 1) * F.W + X0 + 15];  // repeat the last pixel
  end
  else
    for C := -1 to 19 do Yb[WI(-1, C)] := 127;  // no top row: use the constant 127
  // left column and corner
  if MbX > 0 then  // left column exists
  begin
    for R := 0 to 15 do Yb[WI(R, -1)] := F.Y[(Y0 + R) * F.W + X0 - 1];  // copy the pixels on the left
    if MbY > 0 then Yb[WI(-1, -1)] := F.Y[(Y0 - 1) * F.W + X0 - 1] else Yb[WI(-1, -1)] := 127;  // corner pixel
  end
  else
  begin
    for R := 0 to 15 do Yb[WI(R, -1)] := 129;  // no left column: use the constant 129
    if MbY > 0 then Yb[WI(-1, -1)] := 129 else Yb[WI(-1, -1)] := 127;  // corner pixel
  end;
  // the top-right pixels are reused for the blocks in rows 1 to 3 of the right column
  for R := 0 to 2 do  // rows 1 to 3 of the right column
    for C := 16 to 19 do Yb[WI(R * 4 + 3, C)] := Yb[WI(-1, C)];  // reuse the top-right pixels
  if not IsI4 then  // 16x16 prediction
  begin
    Pred16(Yb, 16, IModes[0], MbX, MbY);  // predict the whole block
    for N := 0 to 15 do  // add the residual of each 4x4 block
      if BlkNonZero(Co[N]) then IdctAdd(Co[N], Yb, WI((N shr 2) * 4, (N and 3) * 4));  // add the residual
  end
  else
    for N := 0 to 15 do  // 4x4 prediction
    begin
      Bx := (N and 3) * 4;  // column of the block
      By := (N shr 2) * 4;  // row of the block
      Pred4(Yb, WI(By, Bx), IModes[N]);  // predict the block
      if BlkNonZero(Co[N]) then IdctAdd(Co[N], Yb, WI(By, Bx));  // add the residual
    end;
  for R := 0 to 15 do  // copy the luma block into the frame
    for C := 0 to 15 do F.Y[(Y0 + R) * F.W + X0 + C] := Yb[WI(R, C)];  // copy a row
  // chroma
  Cx0 := MbX * 8;  // chroma x of the macroblock
  Cy0 := MbY * 8;  // chroma y of the macroblock
  for Ch := 0 to 1 do  // both chroma planes
  begin
    FillChar(Ub, SizeOf(Ub), 0);  // clear the working area
    if MbY > 0 then  // top row exists
    begin
      for C := 0 to 7 do  // every column
        if Ch = 0 then Ub[WI(-1, C)] := F.U[(Cy0 - 1) * F.Cw + Cx0 + C]  // copy the pixels above (U plane)
        else Ub[WI(-1, C)] := F.V[(Cy0 - 1) * F.Cw + Cx0 + C];  // copy the pixels above (V plane)
    end
    else
      for C := -1 to 7 do Ub[WI(-1, C)] := 127;  // no top row: use the constant 127
    if MbX > 0 then  // left column exists
    begin
      for R := 0 to 7 do  // every row
        if Ch = 0 then Ub[WI(R, -1)] := F.U[(Cy0 + R) * F.Cw + Cx0 - 1]  // copy the pixels on the left (U plane)
        else Ub[WI(R, -1)] := F.V[(Cy0 + R) * F.Cw + Cx0 - 1];  // copy the pixels on the left (V plane)
      if MbY > 0 then  // corner pixel exists
      begin
        if Ch = 0 then Ub[WI(-1, -1)] := F.U[(Cy0 - 1) * F.Cw + Cx0 - 1]  // corner pixel (U plane)
        else Ub[WI(-1, -1)] := F.V[(Cy0 - 1) * F.Cw + Cx0 - 1];  // corner pixel (V plane)
      end
      else
        Ub[WI(-1, -1)] := 127;  // no top row: 127
    end
    else
    begin
      for R := 0 to 7 do Ub[WI(R, -1)] := 129;  // no left column: use the constant 129
      if MbY > 0 then Ub[WI(-1, -1)] := 129 else Ub[WI(-1, -1)] := 127;  // corner pixel
    end;
    Pred16(Ub, 8, UVMode, MbX, MbY);  // predict the chroma block
    for N := 0 to 3 do  // four 4x4 blocks per plane
    begin
      K := 16 + Ch * 4 + N;  // index of the block in the coefficient list
      if BlkNonZero(Co[K]) then IdctAdd(Co[K], Ub, WI((N shr 1) * 4, (N and 1) * 4));  // add the residual
    end;
    for R := 0 to 7 do  // copy the chroma block into the frame
      for C := 0 to 7 do  // every column
        if Ch = 0 then F.U[(Cy0 + R) * F.Cw + Cx0 + C] := Ub[WI(R, C)]  // copy a pixel (U plane)
        else F.V[(Cy0 + R) * F.Cw + Cx0 + C] := Ub[WI(R, C)];  // copy a pixel (V plane)
  end;
end;

{ ---- loop filter ---- }

{ Limits a value to -128..127. }
function SClip1(V: Integer): Integer; inline;
begin
  if V < -128 then Result := -128 else if V > 127 then Result := 127 else Result := V;  // clamp
end;

{ Limits a value to -16..15. }
function SClip2(V: Integer): Integer; inline;
begin
  if V < -16 then Result := -16 else if V > 15 then Result := 15 else Result := V;  // clamp
end;

{ Loop filter for two pixels across an edge (simple filter). }
procedure DoFilter2(B: PByte; Step: PtrInt);
var
  P1, P0, Q0, Q1, A, A1, A2: Integer;  // P1, P0: pixels before the edge; Q0, Q1: pixels after it; A, A1, A2: filter values
begin
  P1 := B[-2 * Step]; P0 := B[-Step]; Q0 := B[0]; Q1 := B[Step];  // read the four pixels
  A := 3 * (Q0 - P0) + SClip1(P1 - Q1);  // filter strength
  A1 := SClip2(Sar(A + 4, 3));  // adjustment for the pixel after the edge
  A2 := SClip2(Sar(A + 3, 3));  // adjustment for the pixel before the edge
  B[-Step] := Byte(Clip255(P0 + A2));  // filter P0
  B[0] := Byte(Clip255(Q0 - A1));  // filter Q0
end;

{ Loop filter for four pixels across an edge (inner edges). }
procedure DoFilter4(B: PByte; Step: PtrInt);
var
  P1, P0, Q0, Q1, A, A1, A2, A3: Integer;  // P1, P0, Q0, Q1: pixels; A, A1, A2, A3: filter values
begin
  P1 := B[-2 * Step]; P0 := B[-Step]; Q0 := B[0]; Q1 := B[Step];  // read the four pixels
  A := 3 * (Q0 - P0);  // filter strength
  A1 := SClip2(Sar(A + 4, 3));  // adjustment for the pixel after the edge
  A2 := SClip2(Sar(A + 3, 3));  // adjustment for the pixel before the edge
  A3 := (A1 + 1) shr 1;  // half of the first adjustment
  B[-2 * Step] := Byte(Clip255(P1 + A3));  // filter P1
  B[-Step] := Byte(Clip255(P0 + A2));  // filter P0
  B[0] := Byte(Clip255(Q0 - A1));  // filter Q0
  B[Step] := Byte(Clip255(Q1 - A3));  // filter Q1
end;

{ Loop filter for six pixels across an edge (macroblock edges). }
procedure DoFilter6(B: PByte; Step: PtrInt);
var
  P2, P1, P0, Q0, Q1, Q2, A, A1, A2, A3: Integer;  // P2..Q2: pixels; A, A1, A2, A3: filter values
begin
  P2 := B[-3 * Step]; P1 := B[-2 * Step]; P0 := B[-Step];  // read the pixels before the edge
  Q0 := B[0]; Q1 := B[Step]; Q2 := B[2 * Step];  // read the pixels after the edge
  A := SClip1(3 * (Q0 - P0) + SClip1(P1 - Q1));  // filter strength
  A1 := Sar(27 * A + 63, 7);  // strongest adjustment
  A2 := Sar(18 * A + 63, 7);  // middle adjustment
  A3 := Sar(9 * A + 63, 7);  // weakest adjustment
  B[-3 * Step] := Byte(Clip255(P2 + A3));  // filter P2
  B[-2 * Step] := Byte(Clip255(P1 + A2));  // filter P1
  B[-Step] := Byte(Clip255(P0 + A1));  // filter P0
  B[0] := Byte(Clip255(Q0 - A1));  // filter Q0
  B[Step] := Byte(Clip255(Q1 - A2));  // filter Q1
  B[2 * Step] := Byte(Clip255(Q2 - A3));  // filter Q2
end;

{ True when the edge has high variance (strong detail). }
function HevTest(B: PByte; Step: PtrInt; T: Integer): Boolean; inline;
begin
  Result := (Abs(Integer(B[-2 * Step]) - B[-Step]) > T) or (Abs(Integer(B[Step]) - B[0]) > T);  // compare the neighbors with the threshold
end;

{ True when the edge differences are small enough for the simple filter. }
function Needs1(B: PByte; Step: PtrInt; T: Integer): Boolean; inline;
begin
  Result := 4 * Abs(Integer(B[-Step]) - B[0]) + Abs(Integer(B[-2 * Step]) - B[Step]) <= T;  // compare with the threshold
end;

{ True when the edge differences are small enough for the normal filter. }
function Needs2(B: PByte; Step: PtrInt; T, IT: Integer): Boolean;
var
  P3, P2, P1, P0, Q0, Q1, Q2, Q3: Integer;  // P3..Q3: eight pixels across the edge
begin
  P3 := B[-4 * Step]; P2 := B[-3 * Step]; P1 := B[-2 * Step]; P0 := B[-Step];  // read the pixels before the edge
  Q0 := B[0]; Q1 := B[Step]; Q2 := B[2 * Step]; Q3 := B[3 * Step];  // read the pixels after the edge
  if 4 * Abs(P0 - Q0) + Abs(P1 - Q1) > T then  // edge step is too large
  begin
    Result := False;  // do not filter
    Exit;  // done
  end;
  Result := (Abs(P3 - P2) <= IT) and (Abs(P2 - P1) <= IT) and (Abs(P1 - P0) <= IT) and  // inner differences must be small
            (Abs(Q3 - Q2) <= IT) and (Abs(Q2 - Q1) <= IT) and (Abs(Q1 - Q0) <= IT);
end;

{ Applies the simple filter along one edge of Size pixels. }
procedure SimpleLoop(B: PByte; HS, VS: PtrInt; Size, Thresh: Integer);
var
  I, T2: Integer;  // I: pixel along the edge; T2: threshold
begin
  T2 := 2 * Thresh + 1;  // threshold
  for I := 0 to Size - 1 do  // every pixel along the edge
    if Needs1(B + I * VS, HS, T2) then DoFilter2(B + I * VS, HS);  // filter it when needed
end;

{ Applies the normal filter to a macroblock edge (6-pixel filter). }
procedure Loop26(B: PByte; HS, VS: PtrInt; Size, Thresh, IThresh, HevT: Integer);
var
  I, T2: Integer;  // I: pixel along the edge; T2: threshold
  Q: PByte;  // Q: pixel being filtered
begin
  T2 := 2 * Thresh + 1;  // threshold
  for I := 0 to Size - 1 do  // every pixel along the edge
  begin
    Q := B + I * VS;  // pixel position
    if Needs2(Q, HS, T2, IThresh) then  // filter when the edge is smooth enough
    begin
      if HevTest(Q, HS, HevT) then DoFilter2(Q, HS) else DoFilter6(Q, HS);  // filter by edge variance
    end;
  end;
end;

{ Applies the normal filter to an inner edge (4-pixel filter). }
procedure Loop24(B: PByte; HS, VS: PtrInt; Size, Thresh, IThresh, HevT: Integer);
var
  I, T2: Integer;  // I: pixel along the edge; T2: threshold
  Q: PByte;  // Q: pixel being filtered
begin
  T2 := 2 * Thresh + 1;  // threshold
  for I := 0 to Size - 1 do  // every pixel along the edge
  begin
    Q := B + I * VS;  // pixel position
    if Needs2(Q, HS, T2, IThresh) then  // filter when the edge is smooth enough
    begin
      if HevTest(Q, HS, HevT) then DoFilter2(Q, HS) else DoFilter4(Q, HS);  // filter by edge variance
    end;
  end;
end;

{ Applies the loop filter to the edges of one macroblock. }
procedure FilterMb(var F: TFrame; MbX, MbY: Integer; const Fi: TFInfo; FType: Integer);
var
  Yp, Up, Limit, Il, Ht, K: Integer;  // Yp, Up: plane offsets; Limit: edge limit; Il: interior limit; Ht: variance threshold; K: loop counter
  W, Cw: PtrInt;  // W, Cw: luma and chroma width
begin
  Limit := Fi.Limit;  // edge limit
  Il := Fi.ILevel;  // interior limit
  if Limit = 0 then Exit;  // no filtering
  W := F.W;  // luma width
  Cw := F.Cw;  // chroma width
  Yp := MbY * 16 * F.W + MbX * 16;  // luma offset of the macroblock
  Up := MbY * 8 * F.Cw + MbX * 8;  // chroma offset of the macroblock
  if FType = 1 then  // simple filter
  begin
    if MbX > 0 then SimpleLoop(@F.Y[Yp], 1, W, 16, Limit + 4);  // left macroblock edge
    if Fi.Inner <> 0 then  // inner edges
      for K := 1 to 3 do SimpleLoop(@F.Y[Yp + K * 4], 1, W, 16, Limit);  // three inner vertical edges
    if MbY > 0 then SimpleLoop(@F.Y[Yp], W, 1, 16, Limit + 4);  // top macroblock edge
    if Fi.Inner <> 0 then  // inner edges
      for K := 1 to 3 do SimpleLoop(@F.Y[Yp + K * 4 * F.W], W, 1, 16, Limit);  // three inner horizontal edges
  end
  else
  begin
    Ht := Fi.Hev;  // variance threshold
    if MbX > 0 then  // left macroblock edge
    begin
      Loop26(@F.Y[Yp], 1, W, 16, Limit + 4, Il, Ht);  // luma
      Loop26(@F.U[Up], 1, Cw, 8, Limit + 4, Il, Ht);  // U plane
      Loop26(@F.V[Up], 1, Cw, 8, Limit + 4, Il, Ht);  // V plane
    end;
    if Fi.Inner <> 0 then  // inner vertical edges
    begin
      for K := 1 to 3 do Loop24(@F.Y[Yp + K * 4], 1, W, 16, Limit, Il, Ht);  // luma
      Loop24(@F.U[Up + 4], 1, Cw, 8, Limit, Il, Ht);  // U plane
      Loop24(@F.V[Up + 4], 1, Cw, 8, Limit, Il, Ht);  // V plane
    end;
    if MbY > 0 then  // top macroblock edge
    begin
      Loop26(@F.Y[Yp], W, 1, 16, Limit + 4, Il, Ht);  // luma
      Loop26(@F.U[Up], Cw, 1, 8, Limit + 4, Il, Ht);  // U plane
      Loop26(@F.V[Up], Cw, 1, 8, Limit + 4, Il, Ht);  // V plane
    end;
    if Fi.Inner <> 0 then  // inner horizontal edges
    begin
      for K := 1 to 3 do Loop24(@F.Y[Yp + K * 4 * F.W], W, 1, 16, Limit, Il, Ht);  // luma
      Loop24(@F.U[Up + 4 * F.Cw], Cw, 1, 8, Limit, Il, Ht);  // U plane
      Loop24(@F.V[Up + 4 * F.Cw], Cw, 1, 8, Limit, Il, Ht);  // V plane
    end;
  end;
end;

{ decodes one VP8 key frame at Data[Off .. Off + Size) }
procedure DecodeVP8(Data: PByte; DataLen, Off, Size: PtrInt; var F: TFrame; out Width, Height: Integer);
var
  B0, PartLen, P, EndP, SizeLeft, PStart, SzP, PSize, I, J, S, T, Bnd, Cc, K: Integer;  // B0: frame tag; PartLen: first partition size; P: position; EndP: end of the data; SizeLeft: bytes left; PStart: start of the token partitions; SzP: position of the sizes; PSize: partition size; I, J, S, T, Bnd, Cc, K: loop counters
  NParts, Last, FType, Level, Sharp, BaseQ0, MbX, MbY, Seg, X, Y, Ctx, Nz, First, N, Lv, Il: Integer;  // NParts: token partitions; Last: last partition; FType: filter type; Level: filter level; Sharp: sharpness; BaseQ0: base quantizer; MbX, MbY: macroblock position; Seg: segment; X, Y: block position; Ctx: context; Nz: non-zero count; First: first coefficient; N: block number; Lv: filter level of the segment; Il: interior limit
  UseSegment, UpdateMap, AbsDelta, UseLfDelta, UseSkip, Skip, SkipP, Simple: Integer;  // segment, filter and skip flags
  DqY1Dc, DqY2Dc, DqY2Ac, DqUvDc, DqUvAc, Q, UVMode, YM, LeftYM: Integer;  // quantizer deltas and the current quantizer, chroma mode, luma mode
  IsI4, NonZero, SkipEff: Boolean;  // IsI4: 4x4 prediction; NonZero: block has coefficients; SkipEff: effective skip flag
  Br: TBoolDec;  // Br: first partition decoder
  Parts: array of TBoolDec;  // Parts: token partition decoders
  Tbr: ^TBoolDec;  // Tbr: decoder of the current row
  SegQuant, SegFilter: array[0..3] of Integer;  // quantizer and filter level of each segment
  SegProbs: array[0..2] of Integer;  // segment probabilities
  RefD, ModeD: array[0..3] of Integer;  // loop filter deltas
  Qm: array[0..3, 0..2, 0..1] of Integer;  // quantizer step sizes
  Proba: TProbs;  // coefficient probabilities
  FStr: array[0..3, 0..1] of TFInfo;  // filter strengths
  FInfo: array of TFInfo;  // filter info of each macroblock
  TopModes: array of Byte;  // prediction modes of the row above
  TopNz: array of Byte;  // non-zero flags of the row above
  LeftModes: array[0..3] of Integer;  // prediction modes of the blocks on the left
  LeftNz: array[0..8] of Integer;  // non-zero flags of the blocks on the left
  IModes: TBlk;  // prediction modes of the 16 blocks
  Co: TCoefs;  // coefficients of the macroblock
  DcB, Tmp: TBlk;  // DC values and a work block
  A0, A1, A2, A3, Dc: Integer;  // values of the inverse Walsh-Hadamard transform
  Pr: Integer;  // probability index
  Fl: Integer;  // flag
  Cnt: Integer;  // counter
  MbW, MbH: Integer;  // macroblocks across and down

  function CL(V, M: Integer): Integer;  // clamps V to 0..M
  begin
    if V < 0 then Result := 0 else if V > M then Result := M else Result := V;  // clamp
  end;

begin
  if (Size < 10) or (Off + Size > DataLen) then Bad('truncated VP8 data');  // the header needs at least 10 bytes
  B0 := Integer(Data[Off]) or (Integer(Data[Off + 1]) shl 8) or (Integer(Data[Off + 2]) shl 16);  // frame tag
  if (B0 and 1) <> 0 then Bad('not a VP8 key frame');  // bit 0 set means an inter frame
  PartLen := B0 shr 5;  // size of the first partition
  if (Data[Off + 3] <> $9D) or (Data[Off + 4] <> $01) or (Data[Off + 5] <> $2A) then  // key frame start code
    Bad('bad VP8 signature');  // report a bad signature
  Width := (Integer(Data[Off + 6]) or (Integer(Data[Off + 7]) shl 8)) and $3FFF;  // picture width
  Height := (Integer(Data[Off + 8]) or (Integer(Data[Off + 9]) shl 8)) and $3FFF;  // picture height
  if (Width = 0) or (Height = 0) then Bad('empty VP8 frame');  // empty picture
  if PartLen > Size - 10 then Bad('bad VP8 partition size');  // first partition must fit
  P := Off + 10;  // start of the first partition
  EndP := Off + Size;  // end of the data
  BInit(Br, Data, P, PartLen);  // start the boolean decoder
  BGet(Br, $80);     // color space
  BGet(Br, $80);     // clamping type
  // segment header
  UseSegment := BGet(Br, $80);  // segmentation on or off
  UpdateMap := 0;  // no map update
  AbsDelta := 0;  // relative values
  for I := 0 to 3 do begin SegQuant[I] := 0; SegFilter[I] := 0; end;  // clear the segment values
  SegProbs[0] := 255; SegProbs[1] := 255; SegProbs[2] := 255;  // default segment probabilities
  if UseSegment <> 0 then  // segmentation is on
  begin
    UpdateMap := BGet(Br, $80);  // segment map is updated
    if BGet(Br, $80) <> 0 then  // segment values are updated
    begin
      AbsDelta := BGet(Br, $80);  // absolute or relative values
      for I := 0 to 3 do
        if BGet(Br, $80) <> 0 then SegQuant[I] := BSigned(Br, 7) else SegQuant[I] := 0;  // quantizer of each segment
      for I := 0 to 3 do
        if BGet(Br, $80) <> 0 then SegFilter[I] := BSigned(Br, 6) else SegFilter[I] := 0;  // filter level of each segment
    end;
    if UpdateMap <> 0 then  // read the map probabilities
      for I := 0 to 2 do
        if BGet(Br, $80) <> 0 then SegProbs[I] := BValue(Br, 8) else SegProbs[I] := 255;  // probability or 255
  end;
  // filter header
  Simple := BGet(Br, $80);  // simple filter
  Level := BValue(Br, 6);  // filter level
  Sharp := BValue(Br, 3);  // sharpness
  UseLfDelta := BGet(Br, $80);  // filter deltas
  for I := 0 to 3 do begin RefD[I] := 0; ModeD[I] := 0; end;  // clear the deltas
  if UseLfDelta <> 0 then  // deltas are on
    if BGet(Br, $80) <> 0 then  // deltas are updated
    begin
      for I := 0 to 3 do
        if BGet(Br, $80) <> 0 then RefD[I] := BSigned(Br, 6);  // reference frame deltas
      for I := 0 to 3 do
        if BGet(Br, $80) <> 0 then ModeD[I] := BSigned(Br, 6);  // mode deltas
    end;
  if Level = 0 then FType := 0 else if Simple <> 0 then FType := 1 else FType := 2;  // filter type: none, simple or normal
  // token partitions
  P := Off + 10 + PartLen;  // start of the partition sizes
  NParts := 1 shl BValue(Br, 2);  // number of token partitions
  Last := NParts - 1;  // index of the last partition
  SzP := P;  // position of the sizes
  PStart := P + 3 * Last;  // start of the first token partition
  if PStart > EndP then Bad('truncated VP8 partitions');  // partitions must fit
  SetLength(Parts, NParts);  // reserve the decoders
  SizeLeft := EndP - PStart;  // bytes left
  for I := 0 to Last - 1 do  // every partition except the last
  begin
    PSize := Integer(Data[SzP]) or (Integer(Data[SzP + 1]) shl 8) or (Integer(Data[SzP + 2]) shl 16);  // partition size (3 bytes)
    Inc(SzP, 3);  // next size
    if PSize > SizeLeft then PSize := SizeLeft;  // limit to the bytes left
    BInit(Parts[I], Data, PStart, PSize);  // start the decoder
    Inc(PStart, PSize);  // next partition
    Dec(SizeLeft, PSize);  // bytes left
  end;
  BInit(Parts[Last], Data, PStart, SizeLeft);  // the last partition takes the rest
  // quantizers
  BaseQ0 := BValue(Br, 7);  // base quantizer
  DqY1Dc := 0; DqY2Dc := 0; DqY2Ac := 0; DqUvDc := 0; DqUvAc := 0;  // no deltas yet
  if BGet(Br, $80) <> 0 then DqY1Dc := BSigned(Br, 4);  // Y1 DC delta
  if BGet(Br, $80) <> 0 then DqY2Dc := BSigned(Br, 4);  // Y2 DC delta
  if BGet(Br, $80) <> 0 then DqY2Ac := BSigned(Br, 4);  // Y2 AC delta
  if BGet(Br, $80) <> 0 then DqUvDc := BSigned(Br, 4);  // UV DC delta
  if BGet(Br, $80) <> 0 then DqUvAc := BSigned(Br, 4);  // UV AC delta
  for I := 0 to 3 do  // every segment
  begin
    if UseSegment <> 0 then  // segmentation is on
    begin
      Q := SegQuant[I];  // segment quantizer
      if AbsDelta = 0 then Q := Q + BaseQ0;  // add the base value
    end
    else
      Q := BaseQ0;  // base quantizer
    Qm[I, 0, 0] := DcTab[CL(Q + DqY1Dc, 127)];  // Y1 DC step
    Qm[I, 0, 1] := AcTab[CL(Q, 127)];  // Y1 AC step
    Qm[I, 1, 0] := DcTab[CL(Q + DqY2Dc, 127)] * 2;  // Y2 DC step
    Qm[I, 1, 1] := Integer((Int64(AcTab[CL(Q + DqY2Ac, 127)]) * 101581) shr 16);  // Y2 AC step
    if Qm[I, 1, 1] < 8 then Qm[I, 1, 1] := 8;  // minimum of 8
    Qm[I, 2, 0] := DcTab[CL(Q + DqUvDc, 117)];  // UV DC step
    Qm[I, 2, 1] := AcTab[CL(Q + DqUvAc, 127)];  // UV AC step
  end;
  BGet(Br, $80);     // refresh entropy probabilities (not needed for one frame)
  // coefficient probabilities
  K := 0;  // index in the tables
  for T := 0 to 3 do  // four block types
    for Bnd := 0 to 7 do  // eight bands
      for Cc := 0 to 2 do  // three contexts
        for I := 0 to 10 do  // eleven probabilities
        begin
          if BGet(Br, UpdP[K]) <> 0 then Proba[T, Bnd, Cc, I] := Byte(BValue(Br, 8))  // updated probability
          else Proba[T, Bnd, Cc, I] := Coef0[K];  // default probability
          Inc(K);  // next index
        end;
  UseSkip := BGet(Br, $80);  // skip flag in use
  SkipP := 0;  // no skip probability yet
  if UseSkip <> 0 then SkipP := BValue(Br, 8);  // read the skip probability

  MbW := (Width + 15) shr 4;  // macroblocks across
  MbH := (Height + 15) shr 4;  // macroblocks down
  F.MbW := MbW;  // remember the width
  F.MbH := MbH;  // remember the height
  F.W := MbW * 16;  // luma width
  F.H := MbH * 16;  // luma height
  F.Cw := F.W div 2;  // chroma width
  SetLength(F.Y, F.W * F.H);  // reserve the luma plane
  SetLength(F.U, F.Cw * (F.H div 2));  // reserve the U plane
  SetLength(F.V, F.Cw * (F.H div 2));  // reserve the V plane
  // filter strengths per segment and per "has 4x4 blocks" flag
  for S := 0 to 3 do  // every segment
  begin
    if UseSegment <> 0 then  // segmentation is on
    begin
      Lv := SegFilter[S];  // segment filter level
      if AbsDelta = 0 then Lv := Lv + Level;  // add the base level
    end
    else
      Lv := Level;  // base level
    for I := 0 to 1 do  // inner edges off and on
    begin
      J := Lv;  // filter level
      if UseLfDelta <> 0 then  // deltas are on
      begin
        J := J + RefD[0];  // add the reference delta
        if I <> 0 then J := J + ModeD[0];  // add the mode delta
      end;
      J := CL(J, 63);  // limit to 0..63
      if J > 0 then  // filtering is on
      begin
        Il := J;  // interior limit
        if Sharp > 0 then  // sharpness is on
        begin
          if Sharp > 4 then Il := Il shr 2 else Il := Il shr 1;  // reduce the limit
          if Il > 9 - Sharp then Il := 9 - Sharp;  // limit by sharpness
        end;
        if Il < 1 then Il := 1;  // at least 1
        FStr[S, I].ILevel := Il;  // interior limit
        FStr[S, I].Limit := 2 * J + Il;  // edge limit
        if J >= 40 then FStr[S, I].Hev := 2 else if J >= 15 then FStr[S, I].Hev := 1  // high variance threshold
        else FStr[S, I].Hev := 0;
        FStr[S, I].Inner := I;  // filter inner edges
      end
      else
      begin
        FStr[S, I].ILevel := 0;  // no interior limit
        FStr[S, I].Limit := 0;  // no edge limit
        FStr[S, I].Hev := 0;  // no variance threshold
        FStr[S, I].Inner := I;  // filter inner edges
      end;
    end;
  end;
  FInfo := nil;  // release any old array
  if FType > 0 then SetLength(FInfo, MbW * MbH);  // filter info needed when filtering
  TopModes := nil;  // release any old array
  SetLength(TopModes, MbW * 4);  // prediction modes of the row above
  TopNz := nil;  // release any old array
  SetLength(TopNz, MbW * 9);  // non-zero flags of the row above
  for I := 0 to High(TopModes) do TopModes[I] := BDC;  // start with DC prediction
  for I := 0 to High(TopNz) do TopNz[I] := 0;  // start with no coefficients

  for MbY := 0 to MbH - 1 do  // every macroblock row
  begin
    for I := 0 to 3 do LeftModes[I] := BDC;  // left modes start with DC prediction
    for I := 0 to 8 do LeftNz[I] := 0;  // left flags start empty
    Tbr := @Parts[MbY and Last];  // token partition of this row
    for MbX := 0 to MbW - 1 do  // every macroblock in the row
    begin
      // intra modes (first partition)
      Seg := 0;  // segment 0 by default
      if UpdateMap <> 0 then  // segment map is updated
      begin
        if BGet(Br, SegProbs[0]) = 0 then Seg := BGet(Br, SegProbs[1])  // read the segment number
        else Seg := BGet(Br, SegProbs[2]) + 2;  // read the segment number
      end;
      if UseSkip <> 0 then Skip := BGet(Br, SkipP) else Skip := 0;  // skip flag
      IsI4 := BGet(Br, 145) = 0;  // 4x4 prediction when the flag is clear
      for I := 0 to 15 do IModes[I] := 0;  // clear the modes
      if not IsI4 then  // 16x16 prediction
      begin
        if BGet(Br, 156) <> 0 then  // luma mode tree
        begin
          if BGet(Br, 128) <> 0 then YM := BTM else YM := BHE;  // TrueMotion or horizontal
        end
        else
        begin
          if BGet(Br, 163) <> 0 then YM := BVE else YM := BDC;  // vertical or DC
        end;
        IModes[0] := YM;  // one mode for the whole block
        for I := 0 to 3 do  // set the neighbors
        begin
          TopModes[MbX * 4 + I] := YM;  // top mode
          LeftModes[I] := YM;  // left mode
        end;
      end
      else
      begin
        for Y := 0 to 3 do  // every row of blocks
        begin
          LeftYM := LeftModes[Y];  // mode on the left
          for X := 0 to 3 do  // every block in the row
          begin
            Pr := (TopModes[MbX * 4 + X] * 10 + LeftYM) * 9;  // probability index from the top and left modes
            I := YModes4[BGet(Br, BModes[Pr])];  // walk the mode tree
            while I > 0 do
              I := YModes4[2 * I + BGet(Br, BModes[Pr + I])];  // next node
            LeftYM := -I;  // mode of the block
            TopModes[MbX * 4 + X] := LeftYM;  // top mode
            IModes[Y * 4 + X] := LeftYM;  // mode of the block
          end;
          LeftModes[Y] := LeftYM;  // left mode for the next row
        end;
      end;
      if BGet(Br, 142) = 0 then UVMode := BDC  // chroma mode
      else if BGet(Br, 114) = 0 then UVMode := BVE  // chroma mode
      else if BGet(Br, 183) <> 0 then UVMode := BTM  // chroma mode
      else UVMode := BHE;
      // residuals (token partition)
      FillChar(Co, SizeOf(Co), 0);  // residuals (token partition): clear the coefficients
      NonZero := False;  // no coefficients yet
      if Skip = 0 then  // not skipped
      begin
        if not IsI4 then  // 16x16 prediction has a DC block
        begin
          FillChar(DcB, SizeOf(DcB), 0);  // clear the DC block
          Ctx := TopNz[MbX * 9 + 8] + LeftNz[8];  // context from the neighbors
          Nz := GetCoeffs(Tbr^, Proba[1], Ctx, Qm[Seg, 1, 0], Qm[Seg, 1, 1], 0, DcB);  // read the DC coefficients
          if Nz > 0 then Fl := 1 else Fl := 0;  // non-zero flag
          TopNz[MbX * 9 + 8] := Fl;  // store for the row below
          LeftNz[8] := Fl;  // store for the block on the right
          // inverse Walsh-Hadamard transform of the 16 DC values
          for I := 0 to 3 do  // every column
          begin
            A0 := DcB[0 + I] + DcB[12 + I];  // even part of the first column
            A1 := DcB[4 + I] + DcB[8 + I];  // odd part of the first column
            A2 := DcB[4 + I] - DcB[8 + I];  // difference of the odd part
            A3 := DcB[0 + I] - DcB[12 + I];  // difference of the even part
            Tmp[0 + I] := A0 + A1;  // first row of the column
            Tmp[8 + I] := A0 - A1;  // third row of the column
            Tmp[4 + I] := A3 + A2;  // second row of the column
            Tmp[12 + I] := A3 - A2;  // fourth row of the column
          end;
          for I := 0 to 3 do
          begin
            Dc := Tmp[0 + I * 4] + 3;  // DC value with rounding
            A0 := Dc + Tmp[3 + I * 4];  // even sum of the row
            A1 := Tmp[1 + I * 4] + Tmp[2 + I * 4];  // odd sum of the row
            A2 := Tmp[1 + I * 4] - Tmp[2 + I * 4];  // odd difference of the row
            A3 := Dc - Tmp[3 + I * 4];  // even difference of the row
            Co[I * 4 + 0][0] := Sar(A0 + A1, 3);  // store the DC of block 0 of the row
            Co[I * 4 + 1][0] := Sar(A3 + A2, 3);  // store the DC of block 1 of the row
            Co[I * 4 + 2][0] := Sar(A0 - A1, 3);  // store the DC of block 2 of the row
            Co[I * 4 + 3][0] := Sar(A3 - A2, 3);  // store the DC of block 3 of the row
          end;
          First := 1;  // the luma blocks start at coefficient 1
          Cnt := 0;      // probability type 0: Y after Y2
        end
        else
        begin
          First := 0;  // the luma blocks start at coefficient 0
          Cnt := 3;      // probability type 3: Y with DC
        end;
        for Y := 0 to 3 do  // every row of luma blocks
          for X := 0 to 3 do  // every luma block in the row
          begin
            Ctx := LeftNz[Y] + TopNz[MbX * 9 + X];  // context from the left and top flags
            Nz := GetCoeffs(Tbr^, Proba[Cnt], Ctx, Qm[Seg, 0, 0], Qm[Seg, 0, 1], First, Co[Y * 4 + X]);  // read the coefficients of the luma block
            if Nz > First then Fl := 1 else Fl := 0;  // remember whether the block has coefficients
            LeftNz[Y] := Fl;  // flag for the next block on the right
            TopNz[MbX * 9 + X] := Fl;  // flag for the next row below
          end;
        for J := 0 to 1 do  // U plane then V plane
          for Y := 0 to 1 do  // every row of chroma blocks
            for X := 0 to 1 do  // every chroma block in the row
            begin
              Ctx := LeftNz[4 + J * 2 + Y] + TopNz[MbX * 9 + 4 + J * 2 + X];  // context from the left and top flags
              Nz := GetCoeffs(Tbr^, Proba[2], Ctx, Qm[Seg, 2, 0], Qm[Seg, 2, 1], 0,  // read the coefficients of the chroma block
                Co[16 + J * 4 + Y * 2 + X]);
              if Nz > 0 then Fl := 1 else Fl := 0;  // remember whether the block has coefficients
              LeftNz[4 + J * 2 + Y] := Fl;  // flag for the next block on the right
              TopNz[MbX * 9 + 4 + J * 2 + X] := Fl;  // flag for the next row below
            end;
        for N := 0 to 23 do  // check all 24 blocks
          if BlkNonZero(Co[N]) then NonZero := True;  // any coefficient means the macroblock is not skipped
        SkipEff := not NonZero;  // skipped when nothing was found
      end
      else
      begin
        for I := 0 to 7 do  // clear the flags of luma and chroma
        begin
          LeftNz[I] := 0;  // left flag
          TopNz[MbX * 9 + I] := 0;  // top flag
        end;
        if not IsI4 then
        begin
          LeftNz[8] := 0;  // clear the DC flag too
          TopNz[MbX * 9 + 8] := 0;  // top DC flag
        end;
        SkipEff := True;  // nothing to filter inside
      end;
      if FType > 0 then  // store the loop filter data
      begin
        if IsI4 then FInfo[MbY * MbW + MbX] := FStr[Seg, 1]  // 4x4 prediction uses the inner-edge strength
        else FInfo[MbY * MbW + MbX] := FStr[Seg, 0];  // 16x16 prediction
        if not SkipEff then FInfo[MbY * MbW + MbX].Inner := 1;  // filter the inner edges when there are coefficients
      end;
      Reconstruct(F, MbX, MbY, IsI4, IModes, UVMode, Co);  // build the pixels of the macroblock
    end;
  end;
  if FType > 0 then  // loop filter after all macroblocks are decoded
    for MbY := 0 to MbH - 1 do
      for MbX := 0 to MbW - 1 do
        FilterMb(F, MbX, MbY, FInfo[MbY * MbW + MbX], FType);  // filter this macroblock
end;

{ ---- YUV to RGB (libwebp's constants) with the "fancy" 9-3-3-1 chroma upsampler ---- }

{ Converts a fixed-point value to a byte value (0..255) with clamping. }
function Clip8(V: Integer): Integer; inline;
begin
  if (V and (-16384)) = 0 then  // value is in range
    Result := V shr 6  // scale down
  else if V < 0 then
    Result := 0  // negative: black
  else
    Result := 255;  // too large: white
end;

{ Writes one RGB pixel converted from Y, U and V. }
procedure PutRgb(O: PByte; Y, U, V: Integer); inline;
var
  Y1: Integer;  // Y1: scaled luma
begin
  Y1 := (Y * 19077) shr 8;  // scale the luma
  O[0] := Byte(Clip8(Y1 + ((V * 26149) shr 8) - 14234));  // red
  O[1] := Byte(Clip8(Y1 - ((U * 6419) shr 8) - ((V * 13320) shr 8) + 8708));  // green
  O[2] := Byte(Clip8(Y1 + ((U * 33050) shr 8) - 17685));  // blue
end;

{ one pair of output rows from the two chroma rows around them; BotY / OutBot are nil for a
  single last row }
procedure UpsamplePair(TopY, BotY, TopU, TopV, CurU, CurV: PByte; Len: Integer;
  OutTop, OutBot: PByte);
var
  Last, X, TLu, TLv, Lu, Lv, Tu, Tv, Cu, Cv, U0, V0, Avg, D12, D03: Integer;  // Last: last chroma pair; X: column; TLu, TLv: chroma above-left; Lu, Lv: chroma below-left; Tu, Tv: chroma above; Cu, Cv: chroma below; U0, V0: edge chroma; Avg, D12, D03: weighted sums
  Ua, Ub, Uc, Ud, Va, Vb, Vc, Vd: Integer;  // Ua..Vd: interpolated chroma for the four output pixels
begin
  Last := (Len - 1) shr 1;  // index of the last chroma pair
  TLu := TopU[0]; TLv := TopV[0];  // chroma above-left
  Lu := CurU[0]; Lv := CurV[0];  // chroma below-left
  U0 := (3 * TLu + Lu + 2) shr 2;  // first pixel of the top row, U
  V0 := (3 * TLv + Lv + 2) shr 2;  // first pixel of the top row, V
  PutRgb(OutTop, TopY[0], U0, V0);  // write the first top pixel
  if BotY <> nil then  // a bottom row exists
  begin
    U0 := (3 * Lu + TLu + 2) shr 2;  // first pixel of the bottom row, U
    V0 := (3 * Lv + TLv + 2) shr 2;  // first pixel of the bottom row, V
    PutRgb(OutBot, BotY[0], U0, V0);  // write the first bottom pixel
  end;
  for X := 1 to Last do  // every interior column pair
  begin
    Tu := TopU[X]; Tv := TopV[X];  // chroma above
    Cu := CurU[X]; Cv := CurV[X];  // chroma below
    Avg := TLu + Tu + Lu + Cu + 8;  // U sum of the four neighbors
    D12 := (Avg + 2 * (Tu + Lu)) shr 3;  // U weight for pixels 1 and 2
    D03 := (Avg + 2 * (TLu + Cu)) shr 3;  // U weight for pixels 0 and 3
    Ua := (D12 + TLu) shr 1; Ub := (D03 + Tu) shr 1;  // U for the top left and top right pixels
    Uc := (D03 + Lu) shr 1;  Ud := (D12 + Cu) shr 1;  // U for the bottom left and bottom right pixels
    Avg := TLv + Tv + Lv + Cv + 8;  // V sum of the four neighbors
    D12 := (Avg + 2 * (Tv + Lv)) shr 3;  // V weight for pixels 1 and 2
    D03 := (Avg + 2 * (TLv + Cv)) shr 3;  // V weight for pixels 0 and 3
    Va := (D12 + TLv) shr 1; Vb := (D03 + Tv) shr 1;  // V for the top left and top right pixels
    Vc := (D03 + Lv) shr 1;  Vd := (D12 + Cv) shr 1;  // V for the bottom left and bottom right pixels
    PutRgb(OutTop + (2 * X - 1) * 3, TopY[2 * X - 1], Ua, Va);  // top row, left pixel of the pair
    PutRgb(OutTop + (2 * X) * 3, TopY[2 * X], Ub, Vb);  // top row, right pixel of the pair
    if BotY <> nil then  // a bottom row exists
    begin
      PutRgb(OutBot + (2 * X - 1) * 3, BotY[2 * X - 1], Uc, Vc);  // bottom row, left pixel of the pair
      PutRgb(OutBot + (2 * X) * 3, BotY[2 * X], Ud, Vd);  // bottom row, right pixel of the pair
    end;
    TLu := Tu; TLv := Tv;  // shift the top chroma on
    Lu := Cu; Lv := Cv;  // shift the bottom chroma on
  end;
  if (Len and 1) = 0 then  // even width: the last pixel is on its own
  begin
    U0 := (3 * TLu + Lu + 2) shr 2;  // last top pixel, U
    V0 := (3 * TLv + Lv + 2) shr 2;  // last top pixel, V
    PutRgb(OutTop + (Len - 1) * 3, TopY[Len - 1], U0, V0);  // write the last top pixel
    if BotY <> nil then  // a bottom row exists
    begin
      U0 := (3 * Lu + TLu + 2) shr 2;  // last bottom pixel, U
      V0 := (3 * Lv + TLv + 2) shr 2;  // last bottom pixel, V
      PutRgb(OutBot + (Len - 1) * 3, BotY[Len - 1], U0, V0);  // write the last bottom pixel
    end;
  end;
end;

{ Rgb receives Width * Height * 3 bytes }
procedure FrameToRgb(var F: TFrame; Width, Height: Integer; var Rgb: TByteArr);
var
  Y, K, UvH: Integer;  // Y: luma row; K: chroma row
  RowBytes: PtrInt;  // RowBytes: bytes per RGB row
begin
  SetLength(Rgb, Width * Height * 3);  // reserve the RGB buffer
  RowBytes := Width * 3;  // bytes per RGB row
  UvH := (Height + 1) shr 1;  // number of chroma rows
  UpsamplePair(@F.Y[0], nil, @F.U[0], @F.V[0], @F.U[0], @F.V[0], Width, @Rgb[0], nil);  // first row uses only the first chroma row
  Y := 1;  // next luma row
  K := 1;  // next chroma row
  while Y < Height do  // two luma rows per step
  begin
    if K < UvH then  // a following chroma row exists
    begin
      if Y + 1 < Height then  // two rows can be converted together
        UpsamplePair(@F.Y[Y * F.W], @F.Y[(Y + 1) * F.W], @F.U[(K - 1) * F.Cw], @F.V[(K - 1) * F.Cw],
          @F.U[K * F.Cw], @F.V[K * F.Cw], Width, @Rgb[Y * RowBytes], @Rgb[(Y + 1) * RowBytes])
      else  // one last row
        UpsamplePair(@F.Y[Y * F.W], nil, @F.U[(K - 1) * F.Cw], @F.V[(K - 1) * F.Cw],
          @F.U[K * F.Cw], @F.V[K * F.Cw], Width, @Rgb[Y * RowBytes], nil);
    end
    else  // past the last chroma row: reuse it
      UpsamplePair(@F.Y[Y * F.W], nil, @F.U[(K - 1) * F.Cw], @F.V[(K - 1) * F.Cw],
        @F.U[(K - 1) * F.Cw], @F.V[(K - 1) * F.Cw], Width, @Rgb[Y * RowBytes], nil);
    Inc(Y, 2);  // advance two luma rows
    Inc(K);  // advance one chroma row
  end;
end;

{ ---- VP8L (lossless) ---- }

type
  TBitReader = record  // state of the bit reader
    D: PByte;  // data pointer
    P, E: PtrInt;  // P: read position; E: end position
    Acc: QWord;  // bit buffer
    N: Integer;  // number of bits in the buffer
    Over: Integer;  // count of bytes read past the end
  end;

  THuff = record  // prefix (Huffman) code table
    OneSym: Integer;               // >= 0: the only symbol (no bits are read); -1 otherwise
    MaxL: Integer;  // longest code length
    Cnt: array[0..15] of Integer;  // number of codes of each length
    Sorted: array of Word;  // symbols sorted by code
    Fast: array[0..255] of Word;   // (symbol shl 4) or length for codes up to 8 bits
  end;
  THGroup = array[0..4] of THuff;

  TTransform = record  // image transform
    Kind, Bits, W, H: Integer;  // Kind: transform type; Bits: block size bits; W, H: size
    Data: TPix;  // transform data
  end;
  TTransforms = array of TTransform;

const
  CodeLenOrder: array[0..18] of Byte = (17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);  // order in which code length code lengths are stored

{ Refills the bit buffer from the data. }
procedure BRFill(var R: TBitReader);
begin
  while R.N <= 56 do  // fill to at least 57 bits
  begin
    if R.P < R.E then  // bytes remain
      R.Acc := R.Acc or (QWord(R.D[R.P]) shl R.N)  // add the next byte
    else
      Inc(R.Over);  // count bytes past the end
    Inc(R.P);  // next byte
    Inc(R.N, 8);  // 8 more bits in the buffer
  end;
  if R.Over > 16 then Bad('truncated lossless data');  // too far past the end
end;

{ Starts the bit reader on D[Start .. Start + Size). }
procedure BRInit(var R: TBitReader; D: PByte; Start, Size: PtrInt);
begin
  R.D := D;  // data
  R.P := Start;  // start
  R.E := Start + Size;  // end
  R.Acc := 0;  // empty buffer
  R.N := 0;  // no bits
  R.Over := 0;  // no overrun
end;

{ Reads K bits (0..32) from the stream. }
function ReadBits(var R: TBitReader; K: Integer): Integer;
begin
  if K = 0 then  // nothing to read
  begin
    Result := 0;  // zero
    Exit;
  end;
  if R.N < K then BRFill(R);  // refill if needed
  Result := Integer(R.Acc and ((QWord(1) shl K) - 1));  // take the low K bits
  R.Acc := R.Acc shr K;  // drop the bits read
  Dec(R.N, K);  // fewer bits in the buffer
end;

{ Builds the decoding tables of a prefix code from its code lengths. }
procedure BuildHuff(var H: THuff; const Lens: TByteArr; N: Integer);
var
  I, L, Used, Sym1, Code, C, Rv, Fill, Step: Integer;  // I: symbol; L: length; Used: symbols in use; Sym1: last used symbol; Code, C: code values; Rv: reversed code; Fill, Step: fast table helpers
  Offs: array[0..16] of Integer;  // Offs: offset of each length in Sorted
  Nxt: array[0..16] of Integer;  // Nxt: next code of each length
begin
  for L := 0 to 15 do H.Cnt[L] := 0;  // clear the counts
  Used := 0;  // no symbols yet
  Sym1 := 0;  // no symbol yet
  for I := 0 to N - 1 do  // every symbol
    if Lens[I] > 0 then  // symbol is in use
    begin
      Inc(H.Cnt[Lens[I]]);  // count the code length
      Inc(Used);  // count the symbol
      Sym1 := I;  // remember the symbol
    end;
  H.OneSym := -1;  // no single symbol
  H.MaxL := 0;  // no length yet
  for I := 0 to 255 do H.Fast[I] := 0;  // clear the fast table
  H.Sorted := nil;  // clear the sorted list
  if Used <= 1 then  // zero or one symbol
  begin
    if Used = 1 then H.OneSym := Sym1 else H.OneSym := 0;  // the single symbol (or 0)
    Exit;  // nothing more to build
  end;
  for L := 15 downto 1 do  // find the longest length
    if H.Cnt[L] > 0 then
    begin
      H.MaxL := L;  // longest length
      Break;  // stop
    end;
  SetLength(H.Sorted, Used);  // reserve the sorted list
  Offs[1] := 0;  // first offset
  for L := 1 to 15 do Offs[L + 1] := Offs[L] + H.Cnt[L];  // offset of each length
  for I := 0 to N - 1 do  // every symbol
    if Lens[I] > 0 then  // symbol is in use
    begin
      H.Sorted[Offs[Lens[I]]] := Word(I);  // place the symbol
      Inc(Offs[Lens[I]]);  // next slot of the length
    end;
  // canonical codes (first bit read is the top bit of the code)
  Code := 0;  // code of the first length
  Nxt[0] := 0;  // code of length 0
  for L := 1 to 15 do  // first code of each length
  begin
    if L > 1 then Code := (Code + H.Cnt[L - 1]) shl 1 else Code := 0;  // canonical first code
    Nxt[L] := Code;  // remember it
  end;
  for I := 0 to N - 1 do  // every symbol
  begin
    L := Lens[I];  // code length
    if L = 0 then Continue;  // unused symbol
    C := Nxt[L];  // next code of this length
    Inc(Nxt[L]);  // advance
    if C >= (1 shl L) then Bad('bad prefix code');  // code does not fit its length
    if L <= 8 then  // short code: fill the fast table
    begin
      Rv := 0;  // reversed code (bits read lowest first)
      for Step := 0 to L - 1 do  // every bit of the code
        if ((C shr Step) and 1) <> 0 then Rv := Rv or (1 shl (L - 1 - Step));  // reverse the bit order
      Fill := Rv;  // first fast entry
      while Fill < 256 do  // every entry that starts with this code
      begin
        H.Fast[Fill] := Word((I shl 4) or L);  // symbol and length
        Inc(Fill, 1 shl L);  // next entry
      end;
    end;
  end;
end;

{ Reads one symbol using the prefix code H. }
function ReadSym(var R: TBitReader; const H: THuff): Integer;
var
  E, Code, First, Idx, L, Cn: Integer;  // E: fast table entry; Code, First, Idx: canonical decode state; L: length; Cn: count of this length
begin
  if H.OneSym >= 0 then  // single symbol: no bits needed
  begin
    Result := H.OneSym;  // that symbol
    Exit;  // done
  end;
  if R.N < 32 then BRFill(R);  // make sure enough bits are available
  E := H.Fast[R.Acc and 255];  // fast table lookup
  if E <> 0 then  // code of 8 bits or fewer
  begin
    R.Acc := R.Acc shr (E and 15);  // drop the code bits
    Dec(R.N, E and 15);  // fewer bits in the buffer
    Result := E shr 4;  // the symbol
    Exit;  // done
  end;
  Code := 0;  // slow path: code read so far
  First := 0;  // first code of the length
  Idx := 0;  // index into the sorted list
  for L := 1 to H.MaxL do  // try each length
  begin
    Code := Code or Integer(R.Acc and 1);  // add the next bit
    R.Acc := R.Acc shr 1;  // drop the bit
    Dec(R.N);  // one bit less
    Cn := H.Cnt[L];  // codes of this length
    if Code - Cn < First then  // code is within this length
    begin
      Result := H.Sorted[Idx + (Code - First)];  // look up the symbol
      Exit;  // done
    end;
    Inc(Idx, Cn);  // skip the symbols of this length
    First := (First + Cn) shl 1;  // first code of the next length
    Code := Code shl 1;  // make room for the next bit
  end;
  Bad('bad prefix code');  // no valid code found
  Result := 0;
end;

{ Reads a prefix code of ASize symbols from the stream. }
procedure ReadHuffCode(var R: TBitReader; var H: THuff; ASize: Integer);
var
  Lens, Cl: TByteArr;  // Lens: code lengths; Cl: lengths of the code length code
  Hc: THuff;  // Hc: code length code
  NSym, S0, S1, NCl, I, ML, MaxSym, Sym, Prev, C, Rep, Base, ExtraBits, Fill: Integer;  // NSym: simple code symbols; S0, S1: simple code symbols; NCl: code lengths read; I: counter; ML: bits of MaxSym; MaxSym: symbols to read; Sym: current symbol; Prev: last nonzero length; C: code length symbol; Rep: repeat value; Base, ExtraBits: repeat range; Fill: repeat count
begin
  Lens := nil;  // no array yet
  SetLength(Lens, ASize);  // reserve the lengths
  for I := 0 to ASize - 1 do Lens[I] := 0;  // clear the lengths
  if ReadBits(R, 1) <> 0 then  // simple code flag
  begin
    // simple code with one or two symbols
    NSym := ReadBits(R, 1) + 1;  // number of symbols
    if ReadBits(R, 1) <> 0 then S0 := ReadBits(R, 8) else S0 := ReadBits(R, 1);  // first symbol has 1 or 8 bits
    if S0 >= ASize then Bad('bad prefix code');  // out of range
    Lens[S0] := 1;  // first symbol
    if NSym = 2 then  // two symbols
    begin
      S1 := ReadBits(R, 8);  // second symbol
      if S1 >= ASize then Bad('bad prefix code');  // out of range
      Lens[S1] := 1;  // second symbol
    end;
    BuildHuff(H, Lens, ASize);  // build the tables
    Exit;  // done
  end;
  Cl := nil;  // no array yet
  SetLength(Cl, 19);  // 19 code length codes
  for I := 0 to 18 do Cl[I] := 0;  // clear them
  NCl := ReadBits(R, 4) + 4;  // how many are stored
  for I := 0 to NCl - 1 do Cl[CodeLenOrder[I]] := Byte(ReadBits(R, 3));  // read them in the special order
  BuildHuff(Hc, Cl, 19);  // build the code length code
  if ReadBits(R, 1) <> 0 then  // explicit symbol limit
  begin
    ML := 2 + 2 * ReadBits(R, 3);  // bits for the limit
    MaxSym := 2 + ReadBits(R, ML);  // number of symbols to read
    if MaxSym > ASize then Bad('bad prefix code');  // too many
  end
  else
    MaxSym := ASize;  // read all symbols
  Sym := 0;  // start at symbol 0
  Prev := 8;  // default repeat length is 8
  while Sym < ASize do  // until all symbols have lengths
  begin
    if MaxSym = 0 then Break;  // limit reached
    Dec(MaxSym);  // one read used
    C := ReadSym(R, Hc);  // next code length symbol
    if C < 16 then  // literal length
    begin
      Lens[Sym] := Byte(C);  // store the length
      Inc(Sym);  // next symbol
      if C <> 0 then Prev := C;  // remember nonzero lengths
    end
    else
    begin
      case C of
        16: begin Base := 3; ExtraBits := 2; Rep := Prev; end;  // repeat the previous length 3..6 times
        17: begin Base := 3; ExtraBits := 3; Rep := 0; end;  // repeat zero 3..10 times
      else
        begin Base := 11; ExtraBits := 7; Rep := 0; end;  // repeat zero 11..138 times
      end;
      Fill := ReadBits(R, ExtraBits) + Base;  // repeat count
      if Sym + Fill > ASize then Bad('bad prefix code');  // too many
      for I := 1 to Fill do  // fill the lengths
      begin
        Lens[Sym] := Byte(Rep);  // store the length
        Inc(Sym);  // next symbol
      end;
    end;
  end;
  BuildHuff(H, Lens, ASize);  // build the tables
end;

{ Reads a length or distance value from its prefix symbol. }
function PrefixValue(var R: TBitReader; Sym: Integer): Integer;
var
  EB, Offs: Integer;  // EB: extra bits; Offs: base offset
begin
  if Sym < 4 then  // small symbols map directly
  begin
    Result := Sym + 1;  // value is Sym + 1
    Exit;  // done
  end;
  EB := (Sym - 2) shr 1;  // number of extra bits
  Offs := (2 + (Sym and 1)) shl EB;  // offset of the range
  Result := Offs + ReadBits(R, EB) + 1;  // offset plus extra bits
end;

{ Converts a distance code to a pixel distance (2D neighborhood codes). }
function PlaneToDist(Code, W: Integer): Integer;
var
  V, D: Integer;  // V: table entry; D: distance
begin
  if Code > 120 then  // codes above 120 are plain distances
  begin
    Result := Code - 120;  // plain distance
    Exit;  // done
  end;
  V := PlaneTab[Code - 1];  // table entry
  D := (V shr 4) * W + (8 - (V and 15));  // distance from the row and column offsets
  if D < 1 then D := 1;  // at least 1
  Result := D;  // the distance
end;

{ Decodes the entropy-coded pixels (literals, cache hits and backward copies). }
function DecodePixels(var R: TBitReader; W, H: Integer; var Groups: array of THGroup;
  const Meta: TPix; MBits, CCBits: Integer): TPix;
var
  Res: TPix;  // output pixels
  Cache: TPix;  // color cache
  Pos, Total, MW, S, Rr, Bb, Aa, Code, Ln, DSym, DCode, Dist, I, Idx, LastCached: Integer;  // Pos: position; Total: pixel count; MW: meta image width; S: symbol; Rr, Bb, Aa: color channels; Code, Ln, DSym, DCode, Dist: copy parameters; I, Idx: counters; LastCached: last cached position
  V: Cardinal;  // pixel value
  Cur: Integer;  // current prefix group

  function GroupAt(P: Integer): Integer;  // Returns the prefix group index of pixel P.
  begin
    if Length(Meta) = 0 then  // no meta image
      Result := 0  // single group
    else
      Result := Integer((Meta[((P div W) shr MBits) * MW + ((P mod W) shr MBits)] shr 8) and $FFFF);  // group from the meta image
  end;

begin
  Res := nil;  // no array yet
  Cache := nil;  // no array yet
  Total := W * H;  // total pixels
  SetLength(Res, Total);  // reserve the output
  if CCBits > 0 then SetLength(Cache, 1 shl CCBits);  // reserve the color cache
  if CCBits > 0 then  // clear the cache
    for I := 0 to High(Cache) do Cache[I] := 0;  // empty entry
  if MBits > 0 then MW := (W + (1 shl MBits) - 1) shr MBits else MW := 0;  // meta image width in blocks
  Pos := 0;  // first pixel
  LastCached := 0;  // nothing cached yet
  Cur := GroupAt(0);  // group of the first pixel
  while Pos < Total do  // until all pixels are decoded
  begin
    if (Length(Meta) > 0) and ((Pos mod W) and ((1 shl MBits) - 1) = 0) then Cur := GroupAt(Pos);  // load the prefix group at each meta block start
    S := ReadSym(R, Groups[Cur][0]);  // read the green / length / cache symbol
    if S < 256 then  // literal pixel
    begin
      Rr := ReadSym(R, Groups[Cur][1]);  // read red
      Bb := ReadSym(R, Groups[Cur][2]);  // read blue
      Aa := ReadSym(R, Groups[Cur][3]);  // read alpha
      Res[Pos] := (Cardinal(Aa) shl 24) or (Cardinal(Rr) shl 16) or (Cardinal(S) shl 8) or Cardinal(Bb);  // pack the pixel as ARGB
      Inc(Pos);  // next pixel
    end
    else if S < 280 then  // backward copy
    begin
      Code := S - 256;  // length symbol
      Ln := PrefixValue(R, Code);  // copy length
      DSym := ReadSym(R, Groups[Cur][4]);  // distance symbol
      DCode := PrefixValue(R, DSym);  // distance code
      Dist := PlaneToDist(DCode, W);  // distance in pixels
      if (Pos < Dist) or (Total - Pos < Ln) then Bad('bad backward reference');  // reference must stay inside the image
      for I := 0 to Ln - 1 do Res[Pos + I] := Res[Pos + I - Dist];  // copy the pixels
      Inc(Pos, Ln);  // advance past the copy
      if (Length(Meta) > 0) and (Pos < Total) then Cur := GroupAt(Pos);  // update the prefix group
    end
    else
    begin
      if CCBits = 0 then Bad('bad color cache index');  // cache index without a cache
      // put every pixel decoded so far into the cache first
      while LastCached < Pos do  // add all pixels decoded so far to the cache
      begin
        V := Res[LastCached];  // pixel to cache
        Cache[Integer(((QWord(V) * $1E35A7BD) and $FFFFFFFF) shr (32 - CCBits))] := V;  // hash the pixel into the cache
        Inc(LastCached);  // next pixel
      end;
      Idx := S - 280;  // cache index
      if Idx > High(Cache) then Bad('bad color cache index');  // index out of range
      Res[Pos] := Cache[Idx];  // take the pixel from the cache
      Inc(Pos);  // next pixel
    end;
  end;
  Result := Res;  // return the pixels
end;

{ Decodes one entropy-coded image; at the top level it also reads the transforms. }
function DecodeStream(var R: TBitReader; W, H: Integer; Level0: Boolean; var Tr: TTransforms;
  out XSize: Integer): TPix;
var
  Used, T, Bits, BW, BH, NC, I, CCBits, MBits, MW, MH, NGroups, K, G, J, ASize: Integer;  // Used: transforms seen; T: transform type; Bits: block size bits; BW, BH: block grid size; NC: palette colors; I, K, G, J: counters; CCBits: color cache bits; MBits: meta block bits; MW, MH: meta image size; NGroups: prefix groups; ASize: alphabet size
  XS: Integer;  // XS: current width (palette packing shrinks it)
  Data, MImg, Pal: TPix;  // Data: pixels; MImg: meta image; Pal: palette
  Meta: TPix;  // meta image of group numbers
  Groups: array of THGroup;  // prefix groups
  DTr: TTransforms;  // transforms of sub-images (unused)
  DX: Integer;  // width of a sub-image
  A, B: Cardinal;  // A, B: pixel values
begin
  XS := W;  // start with the full width
  Used := 0;  // no transform yet
  Meta := nil;  // no meta image
  DTr := nil;  // no sub-transforms
  if Level0 then  // only the top level has transforms
    while ReadBits(R, 1) <> 0 do  // while another transform follows
    begin
      T := ReadBits(R, 2);  // transform type
      if ((Used shr T) and 1) <> 0 then Bad('transform used twice');  // each type may appear once
      Used := Used or (1 shl T);  // mark it used
      K := Length(Tr);  // index of the new transform
      SetLength(Tr, K + 1);  // add it
      Tr[K].Kind := T;  // type
      Tr[K].W := XS;  // width
      Tr[K].H := H;  // height
      Tr[K].Bits := 0;  // no block bits
      Tr[K].Data := nil;  // no data
      if (T = 0) or (T = 1) then  // predictor or cross-color transform
      begin
        Bits := ReadBits(R, 3) + 2;  // block size bits
        BW := (XS + (1 shl Bits) - 1) shr Bits;  // blocks across
        BH := (H + (1 shl Bits) - 1) shr Bits;  // blocks down
        Tr[K].Bits := Bits;  // remember the block bits
        Tr[K].Data := DecodeStream(R, BW, BH, False, DTr, DX);  // decode the transform data
      end
      else if T = 3 then  // palette transform
      begin
        NC := ReadBits(R, 8) + 1;  // palette size
        if NC > 16 then Bits := 0 else if NC > 4 then Bits := 1 else if NC > 2 then Bits := 2  // pixel packing from the palette size
        else Bits := 3;
        Pal := DecodeStream(R, NC, 1, False, DTr, DX);  // decode the palette
        for I := 1 to NC - 1 do  // palette is delta-coded
        begin
          A := Pal[I];  // this color
          B := Pal[I - 1];  // previous color
          Pal[I] := (((A and $FF00FF00) + (B and $FF00FF00)) and $FF00FF00) or  // add per channel (green and alpha)
                    (((A and $00FF00FF) + (B and $00FF00FF)) and $00FF00FF);  // add per channel (red and blue)
        end;
        SetLength(Pal, 256);  // pad to 256 entries
        for I := NC to 255 do Pal[I] := 0;  // unused entries are transparent black
        Tr[K].Bits := Bits;  // remember the packing
        Tr[K].Data := Pal;  // remember the palette
        XS := (XS + (1 shl Bits) - 1) shr Bits;  // packed width
      end;
    end;
  CCBits := 0;  // no color cache
  if ReadBits(R, 1) <> 0 then  // color cache present
  begin
    CCBits := ReadBits(R, 4);  // cache size bits
    if (CCBits < 1) or (CCBits > 11) then Bad('bad color cache size');  // valid range is 1..11
  end;
  MBits := 0;  // no meta image
  NGroups := 1;  // one prefix group
  if Level0 then  // only the top level has a meta image
    if ReadBits(R, 1) <> 0 then  // meta image present
    begin
      MBits := ReadBits(R, 3) + 2;  // meta block size bits
      MW := (XS + (1 shl MBits) - 1) shr MBits;  // meta image width
      MH := (H + (1 shl MBits) - 1) shr MBits;  // meta image height
      MImg := DecodeStream(R, MW, MH, False, DTr, DX);  // decode the meta image
      Meta := MImg;  // use it for group lookup
      NGroups := 1;  // at least one group
      for I := 0 to High(Meta) do  // find the highest group number
      begin
        J := Integer((Meta[I] shr 8) and $FFFF);  // group number
        if J + 1 > NGroups then NGroups := J + 1;  // keep the largest
      end;
    end;
  Groups := nil;  // no array yet
  SetLength(Groups, NGroups);  // reserve the groups
  for G := 0 to NGroups - 1 do  // every group
    for K := 0 to 4 do  // five codes per group
    begin
      if K = 0 then  // green / length / cache alphabet
      begin
        ASize := 280;  // 256 literals + 24 lengths
        if CCBits > 0 then ASize := ASize + (1 shl CCBits);  // add the cache entries
      end
      else if K = 4 then  // distance alphabet
        ASize := 40  // 40 distance symbols
      else
        ASize := 256;  // red, blue, alpha alphabets
      ReadHuffCode(R, Groups[G][K], ASize);  // read the prefix code
    end;
  Data := DecodePixels(R, XS, H, Groups, Meta, MBits, CCBits);  // decode the pixels
  XSize := XS;  // return the packed width
  Result := Data;  // return the pixels
end;

{ ---- inverse transforms ---- }

{ Adds two ARGB pixels channel by channel (modulo 256). }
function AddPx(A, B: Cardinal): Cardinal; inline;
begin
  Result := (((A and $FF00FF00) + (B and $FF00FF00)) and $FF00FF00) or  // green and alpha channels
            (((A and $00FF00FF) + (B and $00FF00FF)) and $00FF00FF);  // red and blue channels
end;

{ Average of two ARGB pixels per channel. }
function Avg2px(A, B: Cardinal): Cardinal; inline;
begin
  Result := (((A xor B) and $FEFEFEFE) shr 1) + (A and B);  // per-channel average
end;

{ Extracts the channel at bit shift S. }
function Chn(V: Cardinal; S: Integer): Integer; inline;
begin
  Result := Integer((V shr S) and 255);  // shift and mask
end;

{ Predictor 11: chooses the left or top pixel by gradient closeness. }
function SelectPx(L, T, TL: Cardinal): Cardinal;
var
  S, D: Integer;  // S: channel shift; D: sum of differences
begin
  D := 0;  // start at zero
  for S := 0 to 3 do  // every channel
    D := D + Abs(Chn(L, S * 8) - Chn(TL, S * 8)) - Abs(Chn(T, S * 8) - Chn(TL, S * 8));  // compare the distances to the top-left pixel
  if D <= 0 then Result := T else Result := L;  // choose the closer one
end;

{ Predictor 12: L + T - TL, clamped per channel. }
function ClampAddSubFull(A, B, C: Cardinal): Cardinal;
var
  S: Integer;  // S: channel shift
begin
  Result := 0;  // start empty
  for S := 0 to 3 do  // every channel
    Result := Result or (Cardinal(Clip255(Chn(A, S * 8) + Chn(B, S * 8) - Chn(C, S * 8))) shl (S * 8));  // combine the clamped channel
end;

{ Predictor 13: clamped A + (A - B) / 2 per channel. }
function ClampAddSubHalf(A, B: Cardinal): Cardinal;
var
  S, X, Y: Integer;  // S: channel shift; X, Y: channel values
begin
  Result := 0;  // start empty
  for S := 0 to 3 do  // every channel
  begin
    X := Chn(A, S * 8);  // channel of A
    Y := Chn(B, S * 8);  // channel of B
    Result := Result or (Cardinal(Clip255(X + (X - Y) div 2)) shl (S * 8));  // combine the clamped channel
  end;
end;

{ Computes the predicted pixel for a predictor Mode (0..13). }
function PredictPx(Mode: Integer; L, T, TR, TL: Cardinal): Cardinal;
begin
  case Mode of
    1: Result := L;  // left
    2: Result := T;  // top
    3: Result := TR;  // top-right
    4: Result := TL;  // top-left
    5: Result := Avg2px(Avg2px(L, TR), T);  // average of left, top-right and top
    6: Result := Avg2px(L, TL);  // average of left and top-left
    7: Result := Avg2px(L, T);  // average of left and top
    8: Result := Avg2px(TL, T);  // average of top-left and top
    9: Result := Avg2px(T, TR);  // average of top and top-right
    10: Result := Avg2px(Avg2px(L, TL), Avg2px(T, TR));  // average of four neighbors
    11: Result := SelectPx(L, T, TL);  // select by gradient
    12: Result := ClampAddSubFull(L, T, TL);  // clamped gradient
    13: Result := ClampAddSubHalf(Avg2px(L, T), TL);  // clamped half gradient
  else
    Result := $FF000000;  // mode 0 is opaque black
  end;
end;

{ Undoes the predictor transform. }
procedure InvPredictor(var Px: TPix; W, H, Bits: Integer; const Data: TPix);
var
  X, Y, BW, I, Mode: Integer;  // X, Y: position; BW: blocks per row; I: pixel index; Mode: predictor mode
begin
  BW := (W + (1 shl Bits) - 1) shr Bits;  // blocks per row
  Px[0] := AddPx(Px[0], $FF000000);  // first pixel is predicted as opaque black
  for X := 1 to W - 1 do Px[X] := AddPx(Px[X], Px[X - 1]);  // first row is predicted from the left
  for Y := 1 to H - 1 do  // every other row
  begin
    Px[Y * W] := AddPx(Px[Y * W], Px[(Y - 1) * W]);  // first column is predicted from the top
    for X := 1 to W - 1 do  // the rest uses the block mode
    begin
      Mode := Integer((Data[(Y shr Bits) * BW + (X shr Bits)] shr 8) and 15);  // mode of the block
      I := Y * W + X;  // pixel index
      Px[I] := AddPx(Px[I], PredictPx(Mode, Px[I - 1], Px[I - W], Px[I - W + 1], Px[I - W - 1]));  // add the prediction
    end;
  end;
end;

{ Converts a byte to a signed value. }
function SInt8(V: Integer): Integer; inline;
begin
  if V > 127 then Result := V - 256 else Result := V;  // wrap to -128..127
end;

{ Undoes the cross-color transform. }
procedure InvCross(var Px: TPix; W, H, Bits: Integer; const Data: TPix);
var
  X, Y, BW, G2R, G2B, R2B, R, G, B: Integer;  // X, Y: position; BW: blocks per row; G2R, G2B, R2B: multipliers; R, G, B: channels
  M, V: Cardinal;  // M: block multipliers; V: pixel
begin
  BW := (W + (1 shl Bits) - 1) shr Bits;  // blocks per row
  for Y := 0 to H - 1 do  // every row
    for X := 0 to W - 1 do  // every column
    begin
      M := Data[(Y shr Bits) * BW + (X shr Bits)];  // multipliers of the block
      G2R := SInt8(Integer(M and 255));  // green to red
      G2B := SInt8(Integer((M shr 8) and 255));  // green to blue
      R2B := SInt8(Integer((M shr 16) and 255));  // red to blue
      V := Px[Y * W + X];  // current pixel
      R := Integer((V shr 16) and 255);  // red
      G := Integer((V shr 8) and 255);  // green
      B := Integer(V and 255);  // blue
      R := (R + Sar(G2R * SInt8(G), 5)) and 255;  // restore red
      B := (B + Sar(G2B * SInt8(G), 5) + Sar(R2B * SInt8(R), 5)) and 255;  // restore blue
      Px[Y * W + X] := (V and $FF000000) or (Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B);  // pack the pixel
    end;
end;

{ Undoes the subtract-green transform. }
procedure InvSubGreen(var Px: TPix);
var
  I: Integer;  // I: index; V: pixel; G, R, B: channels
  V: Cardinal;
  G, R, B: Cardinal;
begin
  for I := 0 to High(Px) do  // every pixel
  begin
    V := Px[I];  // pixel
    G := (V shr 8) and 255;  // green
    R := (((V shr 16) and 255) + G) and 255;  // restore red
    B := ((V and 255) + G) and 255;  // restore blue
    Px[I] := (V and $FF00FF00) or (R shl 16) or B;  // pack the pixel
  end;
end;

{ Undoes the color indexing (palette) transform. }
procedure InvPalette(var Px: TPix; W, H, Bits: Integer; const Pal: TPix);
var
  X, Y, WP, PerPx, Bpp, Mask, Idx: Integer;  // X, Y: position; WP: packed width; PerPx: indexes per pixel; Bpp: bits per index; Mask: index mask; Idx: palette index
  Res: TPix;  // result pixels
  V: Cardinal;  // V: packed byte
begin
  Res := nil;  // no array yet
  SetLength(Res, W * H);  // reserve the output
  if Bits = 0 then  // one byte per index
  begin
    for X := 0 to W * H - 1 do Res[X] := Pal[(Px[X] shr 8) and 255];  // look up each index
  end
  else
  begin
    WP := (W + (1 shl Bits) - 1) shr Bits;  // packed pixels per row
    PerPx := 1 shl Bits;  // indexes per packed pixel
    Bpp := 8 shr Bits;  // bits per index
    Mask := (1 shl Bpp) - 1;  // mask for one index
    for Y := 0 to H - 1 do  // every row
      for X := 0 to W - 1 do  // every column
      begin
        V := (Px[Y * WP + (X shr Bits)] shr 8) and 255;  // packed byte
        Idx := Integer(V shr ((X and (PerPx - 1)) * Bpp)) and Mask;  // extract the index
        Res[Y * W + X] := Pal[Idx];  // look up the color
      end;
  end;
  Px := Res;  // replace the pixels
end;

{ decodes a lossless image stream (with or without the VP8L header handled by the caller) and
  undoes its transforms; the result has W * H pixels as $AARRGGBB }
function DecodeLossless(var R: TBitReader; W, H: Integer): TPix;
var
  Tr: TTransforms;  // transforms
  Px: TPix;  // pixels
  XS, I: Integer;  // XS: decoded width; I: transform index
begin
  Tr := nil;  // no transforms yet
  Px := DecodeStream(R, W, H, True, Tr, XS);  // decode the pixels
  for I := High(Tr) downto 0 do  // undo the transforms in reverse order
    case Tr[I].Kind of
      0: InvPredictor(Px, Tr[I].W, Tr[I].H, Tr[I].Bits, Tr[I].Data);  // predictor
      1: InvCross(Px, Tr[I].W, Tr[I].H, Tr[I].Bits, Tr[I].Data);  // cross-color
      2: InvSubGreen(Px);  // subtract green
      3: InvPalette(Px, Tr[I].W, Tr[I].H, Tr[I].Bits, Tr[I].Data);  // palette
    end;
  Result := Px;  // return the pixels
end;

{ ---- container ---- }

{ Reads a little-endian 32-bit value. }
function LE32(const D: TByteArr; P: PtrInt): Cardinal; inline;
begin
  Result := Cardinal(D[P]) or (Cardinal(D[P + 1]) shl 8) or (Cardinal(D[P + 2]) shl 16) or  // combine the four bytes
            (Cardinal(D[P + 3]) shl 24);
end;

const
  TagVP8 = $20385056;     // 'VP8 '
  TagVP8L = $4C385056;    // 'VP8L'
  TagALPH = $48504C41;    // 'ALPH'
  TagANMF = $464D4E41;    // 'ANMF'

{ alpha plane of a lossy picture: raw or lossless-compressed, optionally prediction-filtered }
procedure DecodeAlpha(const D: TByteArr; Off, Size, W, H: Integer; var A: TByteArr);
var
  Hdr, Comp, Filt, X, Y, I, P, K: Integer;  // Hdr: header byte; Comp: compression; Filt: filter; X, Y: position; I: index; P: prediction; K: result
  R: TBitReader;  // bit reader
  Px: TPix;  // decoded pixels
begin
  if Size < 1 then Bad('empty alpha chunk');  // chunk too short
  Hdr := D[Off];  // header byte
  Comp := Hdr and 3;  // compression method
  Filt := (Hdr shr 2) and 3;  // prediction filter
  SetLength(A, W * H);  // reserve the alpha plane
  if Comp = 0 then  // uncompressed
  begin
    if Size - 1 < W * H then Bad('truncated alpha');  // data too short
    for I := 0 to W * H - 1 do A[I] := D[Off + 1 + I];  // copy the bytes
  end
  else
  begin
    BRInit(R, @D[0], Off + 1, Size - 1);  // start the bit reader after the header
    Px := DecodeLossless(R, W, H);  // decode the lossless image
    for I := 0 to W * H - 1 do A[I] := Byte((Px[I] shr 8) and 255);  // alpha is in the green channel
  end;
  if Filt = 0 then Exit;  // no filter
  for Y := 0 to H - 1 do  // every row
    for X := 0 to W - 1 do  // every column
    begin
      I := Y * W + X;  // alpha index
      case Filt of  // choose the filter
        1:
          if X = 0 then  // horizontal filter
          begin
            if Y = 0 then P := 0 else P := A[I - W];  // first column uses the pixel above
          end
          else
            P := A[I - 1];  // predict from the left
        2:
          if Y = 0 then  // vertical filter
          begin
            if X = 0 then P := 0 else P := A[I - 1];  // first row uses the pixel on the left
          end
          else
            P := A[I - W];  // predict from above
      else
        if Y = 0 then  // gradient filter
        begin
          if X = 0 then P := 0 else P := A[I - 1];  // first row uses the pixel on the left
        end
        else if X = 0 then
          P := A[I - W]  // first column uses the pixel above
        else
          P := Clip255(Integer(A[I - 1]) + A[I - W] - A[I - W - 1]);  // gradient of the neighbors
      end;
      K := (A[I] + P) and 255;  // add the prediction
      A[I] := Byte(K);  // store the alpha
    end;
end;

{ Decodes a whole WebP file; Rgb receives W * H * 3 bytes (transparent pixels blended with white) }
procedure DecodeWebP(const D: TByteArr; out W, H: Integer; out Rgb: TByteArr);
var
  Pos, Sz, Tag, Q, QEnd, Q2, S2: PtrInt;  // Pos, Sz, Tag: chunk position, size and tag; Q, QEnd, Q2, S2: position, end and next position inside an animation frame
  T2: Cardinal;  // T2: tag of a chunk inside a frame
  ImgTag: Cardinal;  // ImgTag: tag of the picture chunk (0 = none yet)
  ImgOff, ImgSize, AlphOff, AlphSize: PtrInt;  // ImgOff, ImgSize: picture chunk position and size; AlphOff, AlphSize: alpha chunk position and size
  Fr: TFrame;  // decoded lossy frame
  R: TBitReader;  // lossless bit reader
  Px: TPix;  // lossless pixels
  Al: TByteArr;  // alpha plane
  I: Integer;  // pixel counter
  A, Bl: Integer;  // A: alpha; Bl: channel value
begin
  W := 0;  // no width yet
  H := 0;  // no height yet
  Rgb := nil;  // no result yet
  if (Length(D) < 20) or (LE32(D, 0) <> $46464952) or (LE32(D, 8) <> $50424557) then  // must start with RIFF and WEBP
    Bad('not a WebP file');  // not a WebP file
  ImgTag := 0;  // no picture found yet
  ImgOff := 0;  // no picture offset
  ImgSize := 0;  // no picture size
  AlphOff := -1;  // no alpha chunk yet
  AlphSize := 0;  // no alpha size
  Pos := 12;  // chunks start after the 12-byte RIFF header
  while (Pos + 8 <= Length(D)) and (ImgTag = 0) do  // walk the chunks until the picture is found
  begin
    Tag := LE32(D, Pos);  // chunk tag
    Sz := LE32(D, Pos + 4);  // chunk size
    if Pos + 8 + Sz > Length(D) then Sz := Length(D) - Pos - 8;  // limit to the data that exists
    case Tag of  // choose by tag
      TagALPH:
        if AlphOff < 0 then  // use the first alpha chunk only
        begin
          AlphOff := Pos + 8;  // alpha data position
          AlphSize := Sz;  // alpha data size
        end;
      TagVP8, TagVP8L:
        begin
          ImgTag := Tag;  // lossy or lossless picture
          ImgOff := Pos + 8;  // picture data position
          ImgSize := Sz;  // picture data size
        end;
      TagANMF:
        begin
          // first frame of an animation: a 16-byte frame header, then the frame's chunks
          Q := Pos + 8 + 16;  // frame chunks start after the frame header
          QEnd := Pos + 8 + Sz;  // end of the frame
          while (Q + 8 <= QEnd) and (ImgTag = 0) do  // walk the chunks of the frame
          begin
            T2 := LE32(D, Q);  // chunk tag
            S2 := LE32(D, Q + 4);  // chunk size
            if Q + 8 + S2 > QEnd then S2 := QEnd - Q - 8;  // limit to the frame
            if (T2 = TagALPH) and (AlphOff < 0) then  // alpha chunk of the frame
            begin
              AlphOff := Q + 8;  // alpha data position
              AlphSize := S2;  // alpha data size
            end
            else if (T2 = TagVP8) or (T2 = TagVP8L) then  // picture chunk of the frame
            begin
              ImgTag := T2;  // picture type
              ImgOff := Q + 8;  // picture data position
              ImgSize := S2;  // picture data size
            end;
            Q2 := Q + 8 + S2 + (S2 and 1);  // chunks are padded to an even size
            Q := Q2;  // next chunk
          end;
        end;
    end;
    Pos := Pos + 8 + Sz + (Sz and 1);  // next chunk (padded to an even size)
  end;
  if ImgTag = 0 then Bad('no picture data in this WebP file');  // no picture found
  if ImgTag = TagVP8L then  // lossless picture
  begin
    if (ImgSize < 5) or (D[ImgOff] <> $2F) then Bad('bad lossless header');  // check the signature byte
    BRInit(R, @D[0], ImgOff + 1, ImgSize - 1);  // start the bit reader after the signature
    W := ReadBits(R, 14) + 1;  // width
    H := ReadBits(R, 14) + 1;  // height
    ReadBits(R, 1);                      // alpha hint
    if ReadBits(R, 3) <> 0 then Bad('unknown lossless version');  // only version 0 exists
    Px := DecodeLossless(R, W, H);  // decode the pixels
    SetLength(Rgb, W * H * 3);  // reserve the RGB buffer
    for I := 0 to W * H - 1 do  // every pixel
    begin
      A := Integer(Px[I] shr 24);  // alpha of the pixel
      if A = 255 then  // opaque pixel
      begin
        Rgb[I * 3] := Byte((Px[I] shr 16) and 255);  // red
        Rgb[I * 3 + 1] := Byte((Px[I] shr 8) and 255);  // green
        Rgb[I * 3 + 2] := Byte(Px[I] and 255);  // blue
      end
      else
      begin
        Bl := Integer((Px[I] shr 16) and 255);  // red channel
        Rgb[I * 3] := Byte((Bl * A + 255 * (255 - A) + 127) div 255);  // blend red with white
        Bl := Integer((Px[I] shr 8) and 255);  // green channel
        Rgb[I * 3 + 1] := Byte((Bl * A + 255 * (255 - A) + 127) div 255);  // blend green with white
        Bl := Integer(Px[I] and 255);  // blue channel
        Rgb[I * 3 + 2] := Byte((Bl * A + 255 * (255 - A) + 127) div 255);  // blend blue with white
      end;
    end;
    Exit;  // done
  end;
  DecodeVP8(@D[0], Length(D), ImgOff, ImgSize, Fr, W, H);  // decode the lossy picture
  FrameToRgb(Fr, W, H, Rgb);  // convert YUV to RGB
  if AlphOff >= 0 then  // a separate alpha chunk exists
  begin
    Al := nil;  // no array yet
    DecodeAlpha(D, AlphOff, AlphSize, W, H, Al);  // decode the alpha plane
    for I := 0 to W * H - 1 do  // every pixel
    begin
      A := Al[I];  // alpha of the pixel
      if A <> 255 then  // translucent pixel
      begin
        Rgb[I * 3] := Byte((Rgb[I * 3] * A + 255 * (255 - A) + 127) div 255);  // blend red with white
        Rgb[I * 3 + 1] := Byte((Rgb[I * 3 + 1] * A + 255 * (255 - A) + 127) div 255);  // blend green with white
        Rgb[I * 3 + 2] := Byte((Rgb[I * 3 + 2] * A + 255 * (255 - A) + 127) div 255);  // blend blue with white
      end;
    end;
  end;
end;

{ ---- loading ---- }

{ reads and decodes a file, then averages it down by a whole factor so that the long side is
  at least MaxSide (or exactly the picture when it is smaller) }
function RenderWebP(const FileName: string; MaxSide: Integer; out NW, NH: Integer;
  out Pix: TByteArr; out Err: string): Boolean;
var
  Fs: TFileStream;  // file stream
  D: TByteArr;  // file contents
  W, H, K, OX, OY, I, J, Sx, Sy, N, SR, SG, SB, P: Integer;  // W, H: picture size; K: reduction factor; OX, OY: output position; I, J: positions inside a block; Sx, Sy: source position; N: pixels per block; SR, SG, SB: channel sums; P: byte offset
  Rgb: TByteArr;  // decoded RGB pixels
begin
  Result := False;  // assume failure
  Err := '';  // no error
  NW := 0;  // no width
  NH := 0;  // no height
  Pix := nil;  // no pixels
  D := nil;  // no data
  try
    Fs := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);  // open the file for reading
    try
      if Fs.Size > 400 * 1024 * 1024 then Bad('file too large');  // refuse huge files
      SetLength(D, Fs.Size);  // reserve the buffer
      if Length(D) > 0 then Fs.ReadBuffer(D[0], Length(D));  // read the whole file
    finally
      Fs.Free;  // close the file
    end;
    Rgb := nil;  // no pixels yet
    DecodeWebP(D, W, H, Rgb);  // decode the picture
    D := nil;  // release the file data
    K := Max(1, Max(W, H) div Max(1, MaxSide));  // reduction factor (at least 1)
    if K = 1 then  // no reduction needed
    begin
      NW := W;  // output width
      NH := H;  // output height
      Pix := Rgb;  // use the pixels as they are
    end
    else
    begin
      NW := Max(1, W div K);  // output width
      NH := Max(1, H div K);  // output height
      SetLength(Pix, NW * NH * 3);  // reserve the output
      N := K * K;  // pixels per block
      for OY := 0 to NH - 1 do  // every output row
        for OX := 0 to NW - 1 do  // every output column
        begin
          SR := 0; SG := 0; SB := 0;  // clear the sums
          for J := 0 to K - 1 do  // every row of the block
          begin
            Sy := OY * K + J;  // source row
            for I := 0 to K - 1 do  // every column of the block
            begin
              Sx := OX * K + I;  // source column
              P := (Sy * W + Sx) * 3;  // byte offset of the source pixel
              Inc(SR, Rgb[P]);  // add red
              Inc(SG, Rgb[P + 1]);  // add green
              Inc(SB, Rgb[P + 2]);  // add blue
            end;
          end;
          P := (OY * NW + OX) * 3;  // byte offset of the output pixel
          Pix[P] := Byte(SR div N);  // average red
          Pix[P + 1] := Byte(SG div N);  // average green
          Pix[P + 2] := Byte(SB div N);  // average blue
        end;
    end;
    Result := (NW > 0) and (NH > 0);  // success when the picture is not empty
    if not Result then Err := 'empty picture';  // report an empty picture
  except
    on E: Exception do  // report any decoding error
    begin
      Err := E.ClassName + ' ' + E.Message;  // error text
      Result := False;  // failure
    end;
  end;
end;

type
  TBmpFileHdr = packed record  // BMP file header
    bfType: Word;  // signature 'BM'
    bfSize, bfReserved, bfOffBits: LongWord;  // file size, reserved and pixel data offset
  end;
  TBmpInfoHdr = packed record  // BMP info header
    biSize: LongWord;  // header size
    biWidth, biHeight: LongInt;  // width and height
    biPlanes, biBitCount: Word;  // planes and bits per pixel
    biCompression, biSizeImage: LongWord;  // compression and image size
    biXPels, biYPels: LongInt;  // resolution in pixels per meter
    biClrUsed, biClrImportant: LongWord;  // color counts
  end;

{ Decodes a WebP file into a bitmap of about MaxSide pixels. }
function LoadWebPThumb(const FileName: string; MaxSide: Integer; Bmp: TBitmap;
  out Err: string): Boolean;
var
  NW, NH, X, Y, I, LineLen: Integer;  // NW, NH: size; X, Y: position; I: byte offset; LineLen: bytes per BMP row
  Pix, Line: TByteArr;  // Pix: RGB pixels; Line: one BMP row
  Ms: TMemoryStream;  // BMP data in memory
  FH: TBmpFileHdr;  // file header
  IH: TBmpInfoHdr;  // info header
begin
  Result := False;  // assume failure
  if not RenderWebP(FileName, MaxSide, NW, NH, Pix, Err) then Exit;  // decode the picture
  try
    // 24-bit bottom-up BMP, stored as B,G,R
    LineLen := ((NW * 3 + 3) div 4) * 4;  // row length padded to 4 bytes
    Line := nil;  // no array yet
    SetLength(Line, LineLen);  // reserve one row
    FH.bfType := $4D42;  // signature
    FH.bfSize := SizeOf(FH) + SizeOf(IH) + LineLen * NH;  // file size
    FH.bfReserved := 0;  // reserved
    FH.bfOffBits := SizeOf(FH) + SizeOf(IH);  // offset of the pixels
    IH.biSize := SizeOf(IH);  // header size
    IH.biWidth := NW;  // width
    IH.biHeight := NH;  // height
    IH.biPlanes := 1;  // one plane
    IH.biBitCount := 24;  // 24 bits per pixel
    IH.biCompression := 0;  // no compression
    IH.biSizeImage := LineLen * NH;  // image size
    IH.biXPels := 2835;  // horizontal resolution
    IH.biYPels := 2835;  // vertical resolution
    IH.biClrUsed := 0;  // no palette colors
    IH.biClrImportant := 0;  // no important colors
    Ms := TMemoryStream.Create;  // create the memory stream
    try
      Ms.WriteBuffer(FH, SizeOf(FH));  // write the file header
      Ms.WriteBuffer(IH, SizeOf(IH));  // write the info header
      for Y := NH - 1 downto 0 do  // rows go from bottom to top
      begin
        FillChar(Line[0], LineLen, 0);  // clear the padding
        for X := 0 to NW - 1 do  // every column
        begin
          I := (Y * NW + X) * 3;  // byte offset of the pixel
          Line[X * 3] := Pix[I + 2];        // blue
          Line[X * 3 + 1] := Pix[I + 1];    // green
          Line[X * 3 + 2] := Pix[I];        // red
        end;
        Ms.WriteBuffer(Line[0], LineLen);
      end;
      Ms.Position := 0;
      Bmp.LoadFromStream(Ms);  // load the bitmap from the stream
    finally
      Ms.Free;  // free the stream
    end;
    Result := (Bmp.Width > 0) and (Bmp.Height > 0);  // success when the bitmap is not empty
    if not Result then Err := 'empty picture';  // report an empty picture
  except
    on E: Exception do  // report any error
    begin
      Err := E.ClassName + ' ' + E.Message;  // error text
      Result := False;  // failure
    end;
  end;
end;

{ Decodes a WebP file into a memory image of about Target pixels. }
function LoadWebPMemImage(const FileName: string; Target: Integer; out Err: string): TFPMemoryImage;
var
  NW, NH, X, Y, I: Integer;  // NW, NH: size; X, Y: position; I: byte offset
  Pix: TByteArr;  // RGB pixels
  Img: TFPMemoryImage;  // new image
  C: TFPColor;  // pixel color
begin
  Result := nil;  // assume failure
  if not RenderWebP(FileName, Target, NW, NH, Pix, Err) then Exit;  // decode the picture
  try
    Img := TFPMemoryImage.Create(NW, NH);  // create the image
    try
      for Y := 0 to NH - 1 do  // every row
        for X := 0 to NW - 1 do  // every column
        begin
          I := (Y * NW + X) * 3;  // byte offset of the pixel
          C.Red := Word(Pix[I] * 257);  // red as 16 bits
          C.Green := Word(Pix[I + 1] * 257);  // green as 16 bits
          C.Blue := Word(Pix[I + 2] * 257);  // blue as 16 bits
          C.Alpha := $FFFF;  // opaque
          Img.Colors[X, Y] := C;  // set the pixel
        end;
      Result := Img;  // hand the image to the caller
      Img := nil;  // the caller owns it now
    finally
      Img.Free;  // free the image on failure
    end;
  except
    on E: Exception do
    begin
      Err := E.ClassName + ' ' + E.Message;  // error text
      Result := nil;  // failure
    end;
  end;
end;

end.
