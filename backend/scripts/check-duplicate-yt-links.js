#!/usr/bin/env node
/**
 * check-duplicate-yt-links.js
 *
 * Checks YouTube availability for all duplicate production movies
 * using the oEmbed API (0 quota cost).
 * Reports which video IDs are dead/unavailable.
 */

import axios from 'axios'

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

// All duplicate non-cartoon movies (title → [{ id, video_id }])
const DUPLICATES = [
  { title: "A Warm December",           copies: [{ id: "0781fce0-0d33-4fdc-b5db-5742983a5dc2", vid: "seOGzggHVxQ" }, { id: "8730e3f2-19e3-4ad4-b9c8-99b54f48be53", vid: "Vq62D2sd2mE" }, { id: "ffc90fea-0a1c-4f14-8124-86f8cb505ea8", vid: "YJ0VNPPWQZM" }] },
  { title: "Broken Strings",            copies: [{ id: "e90d08d7-75a0-4cdf-a45a-2d37ca4e489a", vid: "JyorpNdI0fI" }, { id: "065e3120-3b38-4348-b4c9-f001024ac334", vid: "A5GxxXlUaG4" }, { id: "63b68388-e225-4e7f-a36b-58f8e821f035", vid: "TmCXZTboXqs" }] },
  { title: "Call of the Yukon",         copies: [{ id: "71ed4940-14bd-4af4-87a6-fb2f7a6fd4f5", vid: "ZD34MQg5gG8" }, { id: "3fe26a23-3f7e-44bb-88f4-304e65549c13", vid: "1Ic57xBzfI0" }, { id: "1fe53c69-1477-41b6-9333-759cb168760c", vid: "TcYD2PDlI2A" }] },
  { title: "Lady Cocoa",                copies: [{ id: "6a1e4c10-3e4c-4a6e-bc83-07318c471a19", vid: "To7eiYk-ltQ" }, { id: "f0b500b6-9223-4629-a20b-78a1b1046d00", vid: "uSwGhSsjaj8" }, { id: "8bf34bdc-8cd9-40a8-a83b-fd5c5e957350", vid: "T633__tjbqs" }] },
  { title: "The Bulldog Breed",         copies: [{ id: "5e73722d-829b-44a7-bba5-66cbfa2cb464", vid: "lO0bQ1p1eyk" }, { id: "5d1ca577-d4fd-412e-8bfe-a7e8530cb9ba", vid: "C5YXUG-xTW8" }, { id: "b4f099f4-728c-4c5f-9cdc-24935addf3ff", vid: "Dzk95tlVlcI" }] },
  { title: "The Crimson Circle",        copies: [{ id: "b160a967-6440-4aa4-a56e-855eacc11eca", vid: "1r6C0vqH53Q" }, { id: "09c3041b-5316-4f15-a602-9a95ecd5727f", vid: "IYAxNsN2eVE" }, { id: "304184a4-0b91-4de3-9335-0f36013b5e9c", vid: "-e8Tck_WOY8" }] },
  { title: "A Bennett Song Holiday",    copies: [{ id: "23c3e95a-b76f-455a-a3a9-5e4e503156da", vid: "KRNsDOuUVtk" }, { id: "900ff7cf-7e52-43a9-b8d8-740266a6ae8e", vid: "TfeSawZ1aDg" }] },
  { title: "A Piece of the Action",     copies: [{ id: "4cedc772-71b0-4c8c-93c6-eb0af7074f7a", vid: "atFDdQVCYK8" }, { id: "1cddbb0f-68bc-4a2c-909e-aeba71fc362e", vid: "lJIqcVKqCZs" }] },
  { title: "Acts of Desperation",       copies: [{ id: "9d5966cc-fa49-4d8d-85f7-be8ca3743d9f", vid: "_HQOSFEQAFE" }, { id: "3801912f-bdbd-48be-ae69-6116aad69137", vid: "ETswxf-XGOA" }] },
  { title: "Albert, R.N.",              copies: [{ id: "1463839d-8cb8-4b06-af7d-16ea1f7fcbba", vid: "hMSggmAK0Is" }, { id: "50706ba5-7c74-421b-b0db-9bc2e13bb671", vid: "GQYlgmzeWBg" }] },
  { title: "Amazon Queen",              copies: [{ id: "5fb75dbd-cd33-4d5a-9e25-ccc6e85025f4", vid: "VRrj0rHweUA" }, { id: "0c2788f5-fec1-4ff4-81a5-0d61b27f023d", vid: "o4OgRZwSTpU" }] },
  { title: "American Justice",          copies: [{ id: "5680174c-e6f6-4d51-8545-e6f4ceaee1b6", vid: "nJQ0aTPkd64" }, { id: "3e8b7fb7-3df3-43a2-a13e-073dfc39aa2e", vid: "WkRGYpzbkjE" }] },
  { title: "Anatomy of a Psycho",       copies: [{ id: "befef9ea-6374-4531-94f5-161effbc847d", vid: "gMHAyimued0" }, { id: "23977e08-d766-41de-a9cf-f7a6459dff53", vid: "1yGCcuBD-Rs" }] },
  { title: "Ben & Ara",                 copies: [{ id: "b4ba8920-0026-49b6-bd94-1f2a76a4c624", vid: "q6-yI0WqCWM" }, { id: "29a7bb4a-fc5e-4017-9da2-b2e941f70a60", vid: "gA6TdZgPXS4" }] },
  { title: "Broken Dreams",             copies: [{ id: "9a3a3175-f1a2-47ec-9c1d-5cdf46499db5", vid: "Dj1089hhONM" }, { id: "db3dbc1b-8b18-4fe7-b22b-5a5bca44e8ce", vid: "qNUfl88N3-o" }] },
  { title: "Brush With Danger",         copies: [{ id: "822aa74f-b815-4aae-a4d7-02351d5fada5", vid: "EsBaNy4EMts" }, { id: "f4149746-7b1b-4ff0-9d4c-82f618a1e4fd", vid: "IOBopQKLAHM" }] },
  { title: "Bulldog Drummond Escapes",  copies: [{ id: "31bc3c25-7f01-49e2-ad31-87316f20672d", vid: "NhrOByCKQY8" }, { id: "3057ec48-96d0-4999-bd06-066b935b4597", vid: "T3Z_NSg0NCo" }] },
  { title: "Captured in Chinatown",     copies: [{ id: "5631f6c6-4f48-4d45-941d-43ddbe166729", vid: "3x2FSkHjk8Q" }, { id: "d0a56baf-4e8c-4ee1-95b9-f4be314e9d9a", vid: "U4b_bJgh2OE" }] },
  { title: "Carbon Copy",               copies: [{ id: "47a8119d-c487-4a82-84ff-834d97f26b61", vid: "mYySBEkoHI0" }, { id: "fd2f473e-b6a4-43d3-82b1-80e4ee96ace7", vid: "843gF8ScpqA" }] },
  { title: "Carter's Army",             copies: [{ id: "97654ab9-3ba9-4d87-84c0-c94237017eb7", vid: "edoYiBoz-4U" }, { id: "0ad24c1d-b9a5-4923-9186-88450bf77a99", vid: "zMIvoQXv_oo" }] },
  { title: "Caught in the Act",         copies: [{ id: "7c908610-a973-4740-8e3b-c850231d5301", vid: "RVPYeNg1AYg" }, { id: "5a817ca3-7b64-4c07-af89-777ee8c970c9", vid: "M87xBJ_RU3w" }] },
  { title: "Cheating Blondes",          copies: [{ id: "11bec642-4040-42bd-91ec-800558b1af04", vid: "6Upqo-NYIgQ" }, { id: "80d6190a-b60d-4f73-8f8a-f5367a1fb52d", vid: "sdazoZDWWgQ" }] },
  { title: "Check and Double Check",    copies: [{ id: "d2297a6e-4c4f-4b04-9133-6302ae5e164f", vid: "2sYsvWGfwrk" }, { id: "86a16977-8de6-4f4a-89e1-a42a0323b705", vid: "O7bRF33EWg4" }] },
  { title: "Cheers of the Crowd",       copies: [{ id: "21894b4c-695b-47ac-a3d6-8d77f3e44466", vid: "zcvfYYo9lEk" }, { id: "76b7b47d-ff01-4a3b-94e9-2aa57afb8ec9", vid: "CQfkpaE9ekU" }] },
  { title: "Circus Girl",               copies: [{ id: "56767591-7984-46a1-8ba7-e924e8631668", vid: "t8X5TtrPZHM" }, { id: "96629394-907f-4fa6-9b53-ba52401be745", vid: "dluf_DB3imY" }] },
  { title: "City Park",                 copies: [{ id: "944aa3bd-f653-4547-bf82-6d22915428c9", vid: "IiICfBGGLiE" }, { id: "7151819a-abe6-4f31-82e8-f6f850c41c22", vid: "93oKVbS6lkY" }] },
  { title: "Clancy in Wall Street",     copies: [{ id: "41d46a90-aa06-4c2d-9830-a65868ef6d4b", vid: "0cmCPikZZO0" }, { id: "3b7cd4db-89c4-413b-b8d3-219edb2b0180", vid: "-E2iS5Z7uZQ" }] },
  { title: "Clarity",                   copies: [{ id: "10b430ec-68d6-4e4e-a3d3-fa3e5990f021", vid: "5MJqAnO_G5M" }, { id: "09f82934-a55a-4315-9e52-271e916abad8", vid: "eXcc-hEn-aM" }] },
  { title: "Club Paradise",             copies: [{ id: "e6c58239-f488-47c7-8987-be261b7d0f49", vid: "dj2u7dYAc5I" }, { id: "00822bc1-65d7-448f-ac60-dbc53a56e92b", vid: "HT094IEaF2Y" }] },
  { title: "Colonel Effingham's Raid",  copies: [{ id: "a77133bd-fd48-4133-8566-18e2e5ce146a", vid: "g7TBjZMVdj8" }, { id: "5285668f-c8ac-4fd6-8f40-874973025443", vid: "wKFC5XKJCTQ" }] },
  { title: "Confidential",              copies: [{ id: "d054f2ac-23cf-459a-81e6-dbce9263f062", vid: "org8f7IZxZo" }, { id: "daad2c3f-fa72-4784-8fa8-275c7f8fce24", vid: "8jvq4GcD7G8" }] },
  { title: "Corregidor",                copies: [{ id: "084e44ed-ea7c-4a7f-af80-4b3472dbd0c4", vid: "ft-MZU-rJ2M" }, { id: "01538b86-8813-48be-b980-96465cc427bd", vid: "6ZuLYCalJOI" }] },
  { title: "Courageous Mr. Penn",       copies: [{ id: "208473c9-6797-426f-aee1-78be2623ca39", vid: "7zoxCsjifzQ" }, { id: "684bcd7d-a515-4dc5-970e-618f6fd0d1f7", vid: "jXFa7kctODg" }] },
  { title: "Crashing Through Danger",   copies: [{ id: "790a6f21-2851-4ce8-baee-3ae6566c7a42", vid: "K0-xK1ORbFg" }, { id: "8dc78145-df52-4d17-a636-f748e6860411", vid: "xYPMFZ1pUd4" }] },
  { title: "Created Equal",             copies: [{ id: "83df7060-f65d-415d-b51e-c7148a62ab2f", vid: "xv5YTv25c3M" }, { id: "b1af8cee-5d44-4e47-9979-ab52ffca3048", vid: "dCalImhNylY" }] },
  { title: "Crimson Romance",           copies: [{ id: "c31ab93c-f818-47ea-a8c7-f0255252dff9", vid: "C7gLqkArDhM" }, { id: "a3dbbce2-e138-4ba6-9662-32d8aafd08d9", vid: "xuwp-0HRt3A" }] },
  { title: "Cross Streets",             copies: [{ id: "f38c049b-5672-4df1-858d-df6448a7bb2c", vid: "2Gbi-Yl9GH8" }, { id: "9c1066e2-e846-482d-84a1-1d4e24ca23a0", vid: "VGKJt74v0OQ" }] },
  { title: "Danger Ahead",              copies: [{ id: "221e7694-a762-49e6-95dc-adc90ad69a88", vid: "KWr5uJB9vO0" }, { id: "dec841fa-15a4-42aa-bd63-bda60f6d8f94", vid: "qeMHbvBJcVA" }] },
  { title: "Danger Lights",             copies: [{ id: "99222a39-69aa-4efb-bd3f-6577fdcbae33", vid: "ZPso4CekamM" }, { id: "f7810ba0-585f-4672-8ccd-75354716723a", vid: "fUju4nIxvhg" }] },
  { title: "Dead on Arrival",           copies: [{ id: "bbf4ad4f-2c3c-40e4-b4a7-1150bc280a1c", vid: "kknA8czT2lY" }, { id: "e25b3e54-c592-451c-b7ff-a05cad8a7b6f", vid: "kGi-HG_7Nlc" }] },
  { title: "Deadly Dance Mom",          copies: [{ id: "ac5f58e4-00b5-4a62-8ece-9cb757ba56e2", vid: "B8gYC00eXZA" }, { id: "e04aa12e-16d4-4974-8e31-ecb9ad43ddf9", vid: "bDaUXonWyUU" }] },
  { title: "Death Fighter",             copies: [{ id: "54d19c67-e55a-4762-ab11-424c13eb3ac3", vid: "PIi1p2QhhNg" }, { id: "56d684a2-bcd4-4a3a-9707-778ac6b4d493", vid: "Zb7QxSs3sKo" }] },
  { title: "Edge of the City",          copies: [{ id: "40e8355c-e796-4434-93f1-954c5240236e", vid: "bFcmHClZe6g" }, { id: "4d4efce5-14a8-4dd8-b3e0-980aabc5fd7c", vid: "Fp39DLWZBwE" }] },
  { title: "Executor",                  copies: [{ id: "067eef77-bbcb-413b-b066-aa7af7ab2661", vid: "JBgrgbLPbXA" }, { id: "059ac3a3-0e3b-4e5e-afab-14cc3eb98e34", vid: "OqsSkFsZXhA" }] },
  { title: "Finding Grace",             copies: [{ id: "327e8188-22d1-4e29-a002-f8ca03826840", vid: "_vOaaQsKBU8" }, { id: "ec61fc41-15cc-49a6-9aa3-5eb840aea2e3", vid: "7WmLMTa50eg" }] },
  { title: "Flood",                     copies: [{ id: "abeea7c3-5e6f-4515-9992-710084755156", vid: "iHNe7k0FvoQ" }, { id: "bb7bc321-2f77-4b7b-8372-1668db7d3dca", vid: "QDnBspYTah8" }] },
  { title: "Ghost Crazy",               copies: [{ id: "7bb00f9d-55f3-4f06-8219-3b4a61c9e917", vid: "2J7geLVYMU4" }, { id: "b3c59b31-5098-4a31-8501-47dab18d1b0d", vid: "QtY0Tu7YZ4E" }] },
  { title: "Green Grow The Rushes",     copies: [{ id: "18537790-4131-433c-a47b-55ec4c6b9362", vid: "iSUtYb9Fd58" }, { id: "0272f2c7-7086-4afd-a34b-173b0d3f5f76", vid: "0wiOVD0zStY" }] },
  { title: "Gung Ho!",                  copies: [{ id: "ed726c28-c381-4825-8ba3-cc0b32bc46ba", vid: "5Mzv4qCJZok" }, { id: "2ecc1d65-d4ea-48ca-9d39-9399f13fb9b5", vid: "TCzNyElUd1w" }] },
  { title: "Half Shot at Sunrise",      copies: [{ id: "1850e0f3-7ef8-4a0e-ae89-5b6708c71b47", vid: "fq0NENzvDhk" }, { id: "b70f5311-5337-469b-ba8a-a453b0641e1f", vid: "pBTox-EFVKQ" }] },
  { title: "Halls of Anger",            copies: [{ id: "2e0305d9-b0d6-4406-8809-341f27ddacf6", vid: "UHtabbBOCYw" }, { id: "91c1eea2-bd3d-4942-b1fd-428cbebce715", vid: "wwrK41Fdqe0" }] },
  { title: "Hope Dances",               copies: [{ id: "4a5b2706-30dc-42d9-998d-9d3f5ea2d1ae", vid: "scpjfTJm_Io" }, { id: "049beed2-8e4a-49ed-8ab6-273ea2545e08", vid: "96Jb57jA9vA" }] },
  { title: "I Take This Oath",          copies: [{ id: "76081a22-da62-49b8-b436-d2acceaa31c0", vid: "NQkgHz4cnGU" }, { id: "246bcdaf-c51a-4fee-9530-ac88604641f0", vid: "nuP8qn59NJI" }] },
  { title: "Jamaica Inn",               copies: [{ id: "72218fb0-003d-44ca-8611-10722705008d", vid: "8qX4SWFKZR4" }, { id: "3262809d-6357-410f-9a46-6d6653a1c837", vid: "07p8w1N58j0" }] },
  { title: "Life with Father",          copies: [{ id: "515ab4dc-1b44-4f9d-870b-20d86077c493", vid: "0vNhr-sUcHA" }, { id: "ff4c294c-5c81-460e-a167-6fdcafc0c2cd", vid: "HvyKMk99vKw" }] },
  { title: "Mega Lightning 2",          copies: [{ id: "c6126cb2-808c-478c-af73-ead3ac66b7ed", vid: "GBeQm9e14j0" }, { id: "60368353-b58e-4878-8b8d-e18a7b4fe135", vid: "TsDQsmPIwjU" }] },
  { title: "Oxygen",                    copies: [{ id: "3288806b-fceb-491a-a7d7-0192c27d54ab", vid: "eizlUVyMoT0" }, { id: "002f06cd-7a1c-4a54-bb0b-f3ae80d5c06b", vid: "-NzY35V_QVU" }] },
  { title: "Pressure Point",            copies: [{ id: "be20553e-04b2-4e63-b2da-a205ce53e962", vid: "YnnbshZxjZI" }, { id: "c25b7078-9376-428f-82a9-311b52f52e2d", vid: "NA0JZBhNolk" }] },
  { title: "Red Ball Express",          copies: [{ id: "eb99c043-215c-4f66-a614-89a303f64550", vid: "iC0DD95BffM" }, { id: "093bcecc-2c81-4583-bc5b-38cb7b64d982", vid: "VZeDB5xmWeM" }] },
  { title: "Sasquatch Mountain",        copies: [{ id: "41ee036d-7af1-4504-8969-295a7f5409be", vid: "cFoQTVZZijQ" }, { id: "54ee51cd-9e63-4c38-9101-20020b30326d", vid: "qGc_sRntIE4" }] },
  { title: "Take a Giant Step",         copies: [{ id: "fa666d10-020e-41f7-a7a3-b558bf601414", vid: "XzCipsta9uY" }, { id: "5b583603-846b-4347-a4ec-6ddfc3d4050e", vid: "RllkoSLqpHs" }] },
  { title: "The Bigamist",              copies: [{ id: "f3488ac8-1065-4486-8e2c-e1dd357edee1", vid: "U3Ma9JubGtg" }, { id: "9260237c-3506-4a34-8206-8389748375cd", vid: "4Et-0iQuyXc" }] },
  { title: "The Brother from Another Planet", copies: [{ id: "158e5bda-b931-4377-96aa-aacbe657ce1c", vid: "fryniHBfpQU" }, { id: "5dc6a92b-b65a-4849-b575-df87151406a9", vid: "fLY0h0uA38A" }] },
  { title: "The Card",                  copies: [{ id: "27fd6959-cfcd-4640-8126-04b7ae497c68", vid: "1dpnkFTM6hg" }, { id: "588f443d-8bd4-4bed-9b17-c9f03f234b79", vid: "LUwllTKK8BQ" }] },
  { title: "The Challenge",             copies: [{ id: "6e494a3f-8a17-42be-921e-0b17293efa14", vid: "wuVjPFrqJoo" }, { id: "5cd34e54-23fc-45f0-b106-04894bd2de47", vid: "s_5y0jX-8-c" }] },
  { title: "The Congressman",           copies: [{ id: "45c3ff89-6eab-4be2-96cf-d10ea8b040a6", vid: "fQKQsoRXEo8" }, { id: "4cbe3636-31d4-4a19-8ffb-2a69858d3c4d", vid: "Hs2PsSLCCA4" }] },
  { title: "The Crusader",              copies: [{ id: "315fc286-16ee-4787-822d-8ba93d09a794", vid: "w8vD3pGCAgY" }, { id: "75b3452c-4b30-461b-ad0c-e3bae1970794", vid: "DypndPzB6Vo" }] },
  { title: "The Curtain Falls",         copies: [{ id: "eb505e8e-1e97-43ec-86e6-cc555d837b0f", vid: "u2HJ7PVDDEg" }, { id: "ea47900e-812f-4595-b0c7-4154af571c81", vid: "JsEvnN2jgQg" }] },
  { title: "The Employer",              copies: [{ id: "9dd5d371-80b1-47f3-97ea-0d475ffa278c", vid: "JfUBB6NFdi0" }, { id: "09468d6e-242d-4576-9b5d-6e791530399a", vid: "9tBypmwhFro" }] },
  { title: "The Girl from Calgary",     copies: [{ id: "4387916d-107d-44e4-9799-eb17e4da825c", vid: "AqcxjGwENl4" }, { id: "8155f1bd-01d0-44db-a506-e7dfaa4e09a6", vid: "NVogCWI-2mw" }] },
  { title: "The Girl from Monterrey",   copies: [{ id: "dfe9eb0f-1a42-40d1-a4f3-ebcc72b309ea", vid: "npIRbsYV4l8" }, { id: "a2433e64-db1c-44af-8b8d-0e15600e063a", vid: "ufxvoV837mQ" }] },
  { title: "The Liberation of L.B. Jones", copies: [{ id: "eae56c9a-96b9-436e-b87e-6afee00216cc", vid: "zVk5hO2N_1A" }, { id: "7b8cd384-ac5c-4712-b1ef-59bc408b8be1", vid: "eua7AzJRlZE" }] },
  { title: "The Marva Collins Story",   copies: [{ id: "6f31b007-40aa-4a6b-8ff5-72e58030f34a", vid: "1igvgmcZOHw" }, { id: "907ccc19-338e-4857-a8e4-c2ab5318e661", vid: "f_XuM8_Qpcc" }] },
  { title: "The Slams",                 copies: [{ id: "060c8f77-bb81-44e8-811b-c067a8b87249", vid: "0QzFP7Ntxhw" }, { id: "c356e0f0-1d91-4100-9c36-1e49ec107fce", vid: "haadms_43HY" }] },
  { title: "The Trail",                 copies: [{ id: "c9e9c657-3b80-441b-82b6-5084776f6bb1", vid: "LP_6wgtM47k" }, { id: "b482ecc2-2a0d-4c97-a9d6-8871dcabbf29", vid: "ZSsJ-LfmBuk" }] },
  { title: "Three of a kind",           copies: [{ id: "4f66b41b-a0eb-4900-8ef3-952e04078e00", vid: "JMKMW7OVsVs" }, { id: "9b4e9ad9-d8b1-4c1b-8c63-ac76964bb4f9", vid: "iyXIKaJm2v0" }] },
  { title: "Uncle Tom's Cabin",         copies: [{ id: "95fd27e7-6711-4088-bdfb-9c69589f787b", vid: "6YRkMYlecTU" }, { id: "542a4223-8902-4f3e-bc57-2c2cb7d8b895", vid: "ncBL1b01dCg" }] },
]

async function checkVideo(videoId) {
  try {
    const res = await axios.get('https://www.youtube.com/oembed', {
      params: { url: `https://www.youtube.com/watch?v=${videoId}`, format: 'json' },
      timeout: 8000,
      validateStatus: null
    })
    return res.status === 200 ? 'live' : 'dead'
  } catch {
    return 'dead'
  }
}

async function main() {
  console.log('🔍 Checking YouTube links for duplicate production movies...\n')

  const deadMovies = []   // all copies dead
  const mixedMovies = []  // some dead, some live
  const allLiveMovies = []

  for (const movie of DUPLICATES) {
    const results = []
    for (const copy of movie.copies) {
      const status = await checkVideo(copy.vid)
      results.push({ ...copy, status })
      process.stdout.write(status === 'live' ? '.' : 'X')
      await sleep(200)
    }
    console.log(` ${movie.title}`)

    const liveCopies = results.filter(r => r.status === 'live')
    const deadCopies = results.filter(r => r.status === 'dead')

    if (liveCopies.length === 0) {
      deadMovies.push({ title: movie.title, copies: results })
    } else if (deadCopies.length > 0) {
      mixedMovies.push({ title: movie.title, live: liveCopies, dead: deadCopies })
    } else {
      allLiveMovies.push({ title: movie.title, copies: results })
    }
  }

  console.log('\n' + '─'.repeat(60))
  console.log(`\n❌ ALL COPIES DEAD (${deadMovies.length} movies):`)
  for (const m of deadMovies) {
    console.log(`   ${m.title}`)
    for (const c of m.copies) console.log(`      - ${c.vid} (${c.id.slice(0,8)})`)
  }

  console.log(`\n⚠️  MIXED — some dead, some live (${mixedMovies.length} movies):`)
  for (const m of mixedMovies) {
    console.log(`   ${m.title}`)
    for (const c of m.live)  console.log(`      ✅ LIVE: ${c.vid}`)
    for (const c of m.dead)  console.log(`      ❌ DEAD: ${c.vid} → delete id ${c.id}`)
  }

  console.log(`\n✅ ALL COPIES LIVE (${allLiveMovies.length} movies) — true duplicates to deduplicate:`)
  for (const m of allLiveMovies) {
    const [keep, ...remove] = m.copies
    console.log(`   ${m.title} — keep ${keep.vid}, remove: ${remove.map(r => r.vid).join(', ')}`)
  }

  // Summary of IDs to delete
  const toDelete = [
    ...deadMovies.flatMap(m => m.copies.map(c => c.id)),
    ...mixedMovies.flatMap(m => m.dead.map(c => c.id)),
    ...allLiveMovies.flatMap(m => m.copies.slice(1).map(c => c.id)),
  ]
  console.log(`\n📋 Total movie IDs to delete: ${toDelete.length}`)
}

main().catch(console.error)
