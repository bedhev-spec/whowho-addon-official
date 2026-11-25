--[[
The tables derive from Unicode 17.0.0 CaseFolding.txt (statuses C and S).
https://www.unicode.org/Public/17.0.0/ucd/CaseFolding.txt
Data file copyright © 2025 Unicode, Inc.
https://www.unicode.org/license.txt

UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.
Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.
THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.
Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.
]]

local Name = {}
WhowhoPreview.GuildBlacklistName = Name

-- Each range maps every stride-th scalar by the same signed offset.
-- Columns: first scalar, last scalar, stride, offset.
local ranges = {
    { 0x0041, 0x005A, 1, 32 },
    { 0x00C0, 0x00D6, 1, 32 },
    { 0x00D8, 0x00DE, 1, 32 },
    { 0x0100, 0x012E, 2, 1 },
    { 0x0132, 0x0136, 2, 1 },
    { 0x0139, 0x0147, 2, 1 },
    { 0x014A, 0x0176, 2, 1 },
    { 0x0179, 0x017D, 2, 1 },
    { 0x01A0, 0x01A4, 2, 1 },
    { 0x01CB, 0x01DB, 2, 1 },
    { 0x01DE, 0x01EE, 2, 1 },
    { 0x01F8, 0x021E, 2, 1 },
    { 0x0222, 0x0232, 2, 1 },
    { 0x0246, 0x024E, 2, 1 },
    { 0x0388, 0x038A, 1, 37 },
    { 0x0391, 0x03A1, 1, 32 },
    { 0x03A3, 0x03AB, 1, 32 },
    { 0x03D8, 0x03EE, 2, 1 },
    { 0x03FD, 0x03FF, 1, -130 },
    { 0x0400, 0x040F, 1, 80 },
    { 0x0410, 0x042F, 1, 32 },
    { 0x0460, 0x0480, 2, 1 },
    { 0x048A, 0x04BE, 2, 1 },
    { 0x04C1, 0x04CD, 2, 1 },
    { 0x04D0, 0x052E, 2, 1 },
    { 0x0531, 0x0556, 1, 48 },
    { 0x10A0, 0x10C5, 1, 7264 },
    { 0x13F8, 0x13FD, 1, -8 },
    { 0x1C90, 0x1CBA, 1, -3008 },
    { 0x1CBD, 0x1CBF, 1, -3008 },
    { 0x1E00, 0x1E94, 2, 1 },
    { 0x1EA0, 0x1EFE, 2, 1 },
    { 0x1F08, 0x1F0F, 1, -8 },
    { 0x1F18, 0x1F1D, 1, -8 },
    { 0x1F28, 0x1F2F, 1, -8 },
    { 0x1F38, 0x1F3F, 1, -8 },
    { 0x1F48, 0x1F4D, 1, -8 },
    { 0x1F59, 0x1F5F, 2, -8 },
    { 0x1F68, 0x1F6F, 1, -8 },
    { 0x1F88, 0x1F8F, 1, -8 },
    { 0x1F98, 0x1F9F, 1, -8 },
    { 0x1FA8, 0x1FAF, 1, -8 },
    { 0x1FC8, 0x1FCB, 1, -86 },
    { 0x2160, 0x216F, 1, 16 },
    { 0x24B6, 0x24CF, 1, 26 },
    { 0x2C00, 0x2C2F, 1, 48 },
    { 0x2C67, 0x2C6B, 2, 1 },
    { 0x2C80, 0x2CE2, 2, 1 },
    { 0xA640, 0xA66C, 2, 1 },
    { 0xA680, 0xA69A, 2, 1 },
    { 0xA722, 0xA72E, 2, 1 },
    { 0xA732, 0xA76E, 2, 1 },
    { 0xA77E, 0xA786, 2, 1 },
    { 0xA796, 0xA7A8, 2, 1 },
    { 0xA7B4, 0xA7C2, 2, 1 },
    { 0xA7CC, 0xA7DA, 2, 1 },
    { 0xAB70, 0xABBF, 1, -38864 },
    { 0xFF21, 0xFF3A, 1, 32 },
    { 0x10400, 0x10427, 1, 40 },
    { 0x104B0, 0x104D3, 1, 40 },
    { 0x10570, 0x1057A, 1, 39 },
    { 0x1057C, 0x1058A, 1, 39 },
    { 0x1058C, 0x10592, 1, 39 },
    { 0x10C80, 0x10CB2, 1, 64 },
    { 0x10D50, 0x10D65, 1, 32 },
    { 0x118A0, 0x118BF, 1, 32 },
    { 0x16E40, 0x16E5F, 1, 32 },
    { 0x16EA0, 0x16EB8, 1, 27 },
    { 0x1E900, 0x1E921, 1, 34 },
}

local exceptions = {
    [0x00B5] = 0x03BC, [0x0178] = 0x00FF, [0x017F] = 0x0073,
    [0x0181] = 0x0253, [0x0182] = 0x0183, [0x0184] = 0x0185,
    [0x0186] = 0x0254, [0x0187] = 0x0188, [0x0189] = 0x0256,
    [0x018A] = 0x0257, [0x018B] = 0x018C, [0x018E] = 0x01DD,
    [0x018F] = 0x0259, [0x0190] = 0x025B, [0x0191] = 0x0192,
    [0x0193] = 0x0260, [0x0194] = 0x0263, [0x0196] = 0x0269,
    [0x0197] = 0x0268, [0x0198] = 0x0199, [0x019C] = 0x026F,
    [0x019D] = 0x0272, [0x019F] = 0x0275, [0x01A6] = 0x0280,
    [0x01A7] = 0x01A8, [0x01A9] = 0x0283, [0x01AC] = 0x01AD,
    [0x01AE] = 0x0288, [0x01AF] = 0x01B0, [0x01B1] = 0x028A,
    [0x01B2] = 0x028B, [0x01B3] = 0x01B4, [0x01B5] = 0x01B6,
    [0x01B7] = 0x0292, [0x01B8] = 0x01B9, [0x01BC] = 0x01BD,
    [0x01C4] = 0x01C6, [0x01C5] = 0x01C6, [0x01C7] = 0x01C9,
    [0x01C8] = 0x01C9, [0x01CA] = 0x01CC, [0x01F1] = 0x01F3,
    [0x01F2] = 0x01F3, [0x01F4] = 0x01F5, [0x01F6] = 0x0195,
    [0x01F7] = 0x01BF, [0x0220] = 0x019E, [0x023A] = 0x2C65,
    [0x023B] = 0x023C, [0x023D] = 0x019A, [0x023E] = 0x2C66,
    [0x0241] = 0x0242, [0x0243] = 0x0180, [0x0244] = 0x0289,
    [0x0245] = 0x028C, [0x0345] = 0x03B9, [0x0370] = 0x0371,
    [0x0372] = 0x0373, [0x0376] = 0x0377, [0x037F] = 0x03F3,
    [0x0386] = 0x03AC, [0x038C] = 0x03CC, [0x038E] = 0x03CD,
    [0x038F] = 0x03CE, [0x03C2] = 0x03C3, [0x03CF] = 0x03D7,
    [0x03D0] = 0x03B2, [0x03D1] = 0x03B8, [0x03D5] = 0x03C6,
    [0x03D6] = 0x03C0, [0x03F0] = 0x03BA, [0x03F1] = 0x03C1,
    [0x03F4] = 0x03B8, [0x03F5] = 0x03B5, [0x03F7] = 0x03F8,
    [0x03F9] = 0x03F2, [0x03FA] = 0x03FB, [0x04C0] = 0x04CF,
    [0x10C7] = 0x2D27, [0x10CD] = 0x2D2D, [0x1C80] = 0x0432,
    [0x1C81] = 0x0434, [0x1C82] = 0x043E, [0x1C83] = 0x0441,
    [0x1C84] = 0x0442, [0x1C85] = 0x0442, [0x1C86] = 0x044A,
    [0x1C87] = 0x0463, [0x1C88] = 0xA64B, [0x1C89] = 0x1C8A,
    [0x1E9B] = 0x1E61, [0x1E9E] = 0x00DF, [0x1FB8] = 0x1FB0,
    [0x1FB9] = 0x1FB1, [0x1FBA] = 0x1F70, [0x1FBB] = 0x1F71,
    [0x1FBC] = 0x1FB3, [0x1FBE] = 0x03B9, [0x1FCC] = 0x1FC3,
    [0x1FD3] = 0x0390, [0x1FD8] = 0x1FD0, [0x1FD9] = 0x1FD1,
    [0x1FDA] = 0x1F76, [0x1FDB] = 0x1F77, [0x1FE3] = 0x03B0,
    [0x1FE8] = 0x1FE0, [0x1FE9] = 0x1FE1, [0x1FEA] = 0x1F7A,
    [0x1FEB] = 0x1F7B, [0x1FEC] = 0x1FE5, [0x1FF8] = 0x1F78,
    [0x1FF9] = 0x1F79, [0x1FFA] = 0x1F7C, [0x1FFB] = 0x1F7D,
    [0x1FFC] = 0x1FF3, [0x2126] = 0x03C9, [0x212A] = 0x006B,
    [0x212B] = 0x00E5, [0x2132] = 0x214E, [0x2183] = 0x2184,
    [0x2C60] = 0x2C61, [0x2C62] = 0x026B, [0x2C63] = 0x1D7D,
    [0x2C64] = 0x027D, [0x2C6D] = 0x0251, [0x2C6E] = 0x0271,
    [0x2C6F] = 0x0250, [0x2C70] = 0x0252, [0x2C72] = 0x2C73,
    [0x2C75] = 0x2C76, [0x2C7E] = 0x023F, [0x2C7F] = 0x0240,
    [0x2CEB] = 0x2CEC, [0x2CED] = 0x2CEE, [0x2CF2] = 0x2CF3,
    [0xA779] = 0xA77A, [0xA77B] = 0xA77C, [0xA77D] = 0x1D79,
    [0xA78B] = 0xA78C, [0xA78D] = 0x0265, [0xA790] = 0xA791,
    [0xA792] = 0xA793, [0xA7AA] = 0x0266, [0xA7AB] = 0x025C,
    [0xA7AC] = 0x0261, [0xA7AD] = 0x026C, [0xA7AE] = 0x026A,
    [0xA7B0] = 0x029E, [0xA7B1] = 0x0287, [0xA7B2] = 0x029D,
    [0xA7B3] = 0xAB53, [0xA7C4] = 0xA794, [0xA7C5] = 0x0282,
    [0xA7C6] = 0x1D8E, [0xA7C7] = 0xA7C8, [0xA7C9] = 0xA7CA,
    [0xA7CB] = 0x0264, [0xA7DC] = 0x019B, [0xA7F5] = 0xA7F6,
    [0xFB05] = 0xFB06, [0x10594] = 0x105BB, [0x10595] = 0x105BC,
}

local function foldedScalar(scalar)
    local exception = exceptions[scalar]
    if exception then return exception end

    local low, high = 1, #ranges
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local range = ranges[middle]
        if scalar < range[1] then
            high = middle - 1
        elseif scalar > range[2] then
            low = middle + 1
        else
            if (scalar - range[1]) % range[3] == 0 then
                return scalar + range[4]
            end
            return nil
        end
    end
end

local function encodeScalar(scalar)
    if scalar < 0x80 then
        return string.char(scalar)
    end
    local byte4 = 0x80 + scalar % 64
    scalar = math.floor(scalar / 64)
    if scalar < 32 then
        return string.char(0xC0 + scalar, byte4)
    end
    local byte3 = 0x80 + scalar % 64
    scalar = math.floor(scalar / 64)
    if scalar < 16 then
        return string.char(0xE0 + scalar, byte3, byte4)
    end
    local byte2 = 0x80 + scalar % 64
    scalar = math.floor(scalar / 64)
    return string.char(0xF0 + scalar, byte2, byte3, byte4)
end

local function foldUtf8(character)
    local leading = character:byte()
    local scalar = leading
    if #character > 1 then
        local leadingModulus = 2 ^ (7 - #character)
        scalar = leading % leadingModulus
        for i = 2, #character do
            scalar = scalar * 64 + character:byte(i) - 128
        end
    end
    local folded = foldedScalar(scalar)
    if folded then return encodeScalar(folded) end
    return nil -- gsub keeps the original bytes.
end

-- The caller validates the complete name. This is an internal lookup key.
-- Byte ranges select ASCII capitals and multibyte UTF-8 scalars.
function Name.Key(validatedName)
    if type(validatedName) ~= "string" then return nil end
    return (validatedName:gsub("[A-Z\194-\244][\128-\191]*", foldUtf8))
end

-- Use byte order so clients converge on one observed spelling across locales.
function Name.PreferDisplay(a, b)
    if not a then return b end
    if not b then return a end
    for i = 1, math.min(#a, #b) do
        local left, right = a:byte(i), b:byte(i)
        if left < right then return a end
        if left > right then return b end
    end
    if #a <= #b then return a end
    return b
end
