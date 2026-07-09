#!/usr/bin/env node
/**
 * Restore posters for BlackTree TV movies by calling enrich-manual-imdb for each.
 */

import axios from 'axios'

const BACKEND_URL = 'https://movieboxz-backend-production.up.railway.app'
const ADMIN_KEY = process.env.ADMIN_API_KEY
const headers = { 'x-admin-api-key': ADMIN_KEY, 'Content-Type': 'application/json' }

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

// All BlackTree movies with no poster_path, from DB query
const MOVIES = [
  { id: '741b810b-2c4a-4c3e-81c0-aa725abfb58c', title: '100 Rifles', imdb_id: 'tt0063970' },
  { id: '5364070d-ed0f-400b-925c-aea1981d910a', title: 'A Cross to Bear', imdb_id: 'tt2009410' },
  { id: '4cedc772-71b0-4c8c-93c6-eb0af7074f7a', title: 'A Piece of the Action', imdb_id: 'tt0076543' },
  { id: '1cddbb0f-68bc-4a2c-909e-aeba71fc362e', title: 'A Piece of the Action', imdb_id: 'tt0076543' },
  { id: 'ffc90fea-0a1c-4f14-8124-86f8cb505ea8', title: 'A Warm December', imdb_id: 'tt0070898' },
  { id: '0781fce0-0d33-4fdc-b5db-5742983a5dc2', title: 'A Warm December', imdb_id: 'tt0070898' },
  { id: '8730e3f2-19e3-4ad4-b9c8-99b54f48be53', title: 'A Warm December', imdb_id: 'tt0070898' },
  { id: 'fba53ee1-1c39-4648-a5f5-9531c8b9eb1b', title: 'Always and Forever', imdb_id: 'tt7544954' },
  { id: 'b90ef0d0-7716-43b8-aa05-ea9ef4b58cc7', title: 'Anna Lucasta', imdb_id: 'tt0051362' },
  { id: '6ae692db-1f69-45a1-b06e-53c2ca730352', title: "Bill Bellamy's Ladies Night Out Comedy Tour", imdb_id: 'tt2765192' },
  { id: 'b6a9332c-5357-422d-85a4-55483a056507', title: 'Birthright', imdb_id: 'tt0135163' },
  { id: '0415de5a-5a27-45f3-92ca-7552fb666fa2', title: 'Black Tigress', imdb_id: 'tt0157936' },
  { id: '2ff3691f-8b5a-409c-be1e-f46285555a49', title: 'Boarding House Blues', imdb_id: 'tt0040176' },
  { id: '644977a3-ff71-4406-b1b4-680a944431a2', title: 'Booker', imdb_id: 'tt0308059' },
  { id: '7e2f7a1e-3537-4fde-b8f7-9f22ad1a2704', title: 'Borderline', imdb_id: 'tt13650814' },
  { id: '43deafef-1d3c-4cb8-81c7-979d9907a257', title: 'Boycott', imdb_id: 'tt0255851' },
  { id: 'cf24c63a-8b70-40d2-baa4-0e8a33fafba0', title: 'Bright Road', imdb_id: 'tt0045578' },
  { id: '7ea6846e-45b5-4206-947f-c8eceadad21e', title: 'Brother Future', imdb_id: 'tt0264441' },
  { id: '0eb76353-ef5a-4f9f-b5b2-d17804730d12', title: 'Cane River', imdb_id: 'tt0318346' },
  { id: 'fd2f473e-b6a4-43d3-82b1-80e4ee96ace7', title: 'Carbon Copy', imdb_id: 'tt0082138' },
  { id: '47a8119d-c487-4a82-84ff-834d97f26b61', title: 'Carbon Copy', imdb_id: 'tt0082138' },
  { id: '1d313692-8650-4124-9ccd-3ee624d83de7', title: 'Carib Gold', imdb_id: 'tt0264460' },
  { id: '0ad24c1d-b9a5-4923-9186-88450bf77a99', title: "Carter's Army", imdb_id: 'tt0064135' },
  { id: '97654ab9-3ba9-4d87-84c0-c94237017eb7', title: "Carter's Army", imdb_id: 'tt0064135' },
  { id: '47ef042a-797a-47e8-8e07-6bc1a916667c', title: 'Change of Plans', imdb_id: 'tt1790658' },
  { id: 'b99c39f2-156f-490a-98e7-f8e985216837', title: 'Cobra nero', imdb_id: 'tt0092765' },
  { id: '73400832-2e38-45e1-8358-06d334e8fce2', title: 'Cornbread, Earl and Me', imdb_id: 'tt0072822' },
  { id: '3a49ccd9-b44b-4cb6-a9ef-f7a15f142ad5', title: 'Dream Date', imdb_id: 'tt0097234' },
  { id: '3c919dcc-b0be-43cb-aea8-a82cfb951bfa', title: 'Dummy', imdb_id: 'tt0079088' },
  { id: '789128d2-30a6-4d76-bf1b-b36998b68782', title: 'Eddie', imdb_id: 'tt0116168' },
  { id: '4d4efce5-14a8-4dd8-b3e0-980aabc5fd7c', title: 'Edge of the City', imdb_id: 'tt0050347' },
  { id: '40e8355c-e796-4434-93f1-954c5240236e', title: 'Edge of the City', imdb_id: 'tt0050347' },
  { id: '909bb75a-6929-4db1-9ca0-6beee7c3bb2b', title: 'El Diablo', imdb_id: 'tt0099493' },
  { id: '4b0f492d-8efc-4335-9898-34dfe0647c71', title: 'Enemy Territory', imdb_id: 'tt0092969' },
  { id: 'cb3541ce-10c5-482a-82b5-3efffccbbc47', title: 'Firelight', imdb_id: 'tt2281241' },
  { id: 'cd7fce3f-ade2-40e2-92eb-76aeb1f404b6', title: 'First Time Felon', imdb_id: 'tt0119127' },
  { id: '6e358a0d-eaa0-47e2-8b92-bf2a1af28703', title: 'Flesh & Blood', imdb_id: 'tt0079161' },
  { id: 'd3ed6302-6ec5-41b7-828c-1d45ebd7dc6d', title: 'For Love of Ivy', imdb_id: 'tt0062985' },
  { id: 'bc244ec7-05c4-4c04-9d6d-1de31b4b6188', title: 'For the Love of Ruth', imdb_id: 'tt4526656' },
  { id: '5428b625-7b28-4e97-9904-5e88a8cc89a3', title: 'Formula 51', imdb_id: 'tt0227984' },
  { id: '215e3702-1e0f-4b4d-9bb6-ed02d9024e05', title: 'Gardens of Stone', imdb_id: 'tt0093073' },
  { id: 'e1a82de6-f524-4506-ba3a-870ec5775d65', title: 'George Washington', imdb_id: 'tt0262432' },
  { id: 'da464075-d6fa-4ffd-abd4-460d290daf9e', title: 'Ghost of a Chance', imdb_id: 'tt0249537' },
  { id: 'e532fd79-4c2d-4c81-a9bf-0db9868a9556', title: 'Go Down, Moses', imdb_id: 'tt0592443' },
  { id: '6bedcbf3-6613-4784-bbcf-7d973df902bc', title: 'Hallelujah', imdb_id: 'tt0019959' },
  { id: '91c1eea2-bd3d-4942-b1fd-428cbebce715', title: 'Halls of Anger', imdb_id: 'tt0065810' },
  { id: '2e0305d9-b0d6-4406-8809-341f27ddacf6', title: 'Halls of Anger', imdb_id: 'tt0065810' },
  { id: '5a18a506-0326-4711-ad22-90c6b1ca2e6c', title: "He's a Legend, He's a Hero", imdb_id: 'tt5761646' },
  { id: '17cbac7a-1f3c-49ff-860f-17eb7cc1df63', title: 'Heist', imdb_id: 'tt0252503' },
  { id: '6f9ff86f-1a4b-4629-9225-12113f48a7db', title: 'Holiday Heart', imdb_id: 'tt0250425' },
  { id: '72f3119b-bc99-4ee7-9a3a-ca5a7c319dde', title: 'Hopelessly in June', imdb_id: 'tt1349616' },
  { id: 'df32526d-87a6-477a-b0b3-323cf3224644', title: 'If He Hollers, Let Him Go!', imdb_id: 'tt0063124' },
  { id: 'a560f449-a14e-4382-a542-aeed4b825d83', title: 'Island in the Sun', imdb_id: 'tt0050549' },
  { id: '719f2368-5005-4a93-9eb6-d17edf1deae0', title: "J.D.'s Revenge", imdb_id: 'tt0074703' },
  { id: 'e3466a4a-e4f9-4160-83c9-5b93c149e7c6', title: 'Jasper, Texas', imdb_id: 'tt0335185' },
  { id: '556269e4-1e66-4429-bbef-5981cda50253', title: 'Judge Horton and the Scottsboro Boys', imdb_id: 'tt0074723' },
  { id: '4dc786b0-ab01-4f67-8871-7ec68b3239cd', title: 'Killer Force', imdb_id: 'tt0073241' },
  { id: '67de6264-2d59-4076-a55f-b575062a5d40', title: 'Killpoint', imdb_id: 'tt0087556' },
  { id: 'c564bbc2-c009-4d32-85f1-ea3bd175d713', title: 'Lackawanna Blues', imdb_id: 'tt0407936' },
  { id: 'f0b500b6-9223-4629-a20b-78a1b1046d00', title: 'Lady Cocoa', imdb_id: 'tt0073259' },
  { id: '6a1e4c10-3e4c-4a6e-bc83-07318c471a19', title: 'Lady Cocoa', imdb_id: 'tt0073259' },
  { id: '1afa1f83-48cd-4181-b084-c3d6441038c3', title: 'Lavell Crawford: Can a Brother Get Some Love', imdb_id: 'tt2084872' },
  { id: '9415a349-990a-43a2-9ba6-97df9e954d4e', title: "Let's Do It Again", imdb_id: 'tt0073282' },
  { id: 'cac26821-57a1-4914-b97f-bd763a65311a', title: 'Martin Lawrence: You So Crazy', imdb_id: 'tt0111804' },
  { id: '740129bc-cfd4-4227-b341-f59449c222b8', title: 'Mayday at 40, 000 Feet!', imdb_id: 'tt0074881' },
  { id: '576e8879-f66c-433c-b046-c9c51fe3d073', title: 'Mike Epps: Under Rated... Never Faded & X-Rated', imdb_id: 'tt1636817' },
  { id: '7c447f4d-785d-49b3-aa72-2709959444cd', title: 'Mikolo', imdb_id: 'tt28648037' },
  { id: '3029384f-842c-4116-ba3a-fdfc19d11a06', title: 'Minstrel Man', imdb_id: 'tt0037076' },
  { id: 'ca90060e-d65c-412e-9f39-28150631aab0', title: "Miss Evers' Boys", imdb_id: 'tt0119679' },
  { id: 'e6a4687e-7d02-4298-9424-2cab09e03eae', title: 'Muhammad Ali: Through the Eyes of the World', imdb_id: 'tt0404251' },
  { id: '9733cda0-25c6-48b9-b32b-d738733ae15b', title: 'Murder in Harlem', imdb_id: 'tt0026741' },
  { id: 'eebe6065-5d75-4fac-b786-035d1d091828', title: 'Mysterious Island of Beautiful Women', imdb_id: 'tt0079598' },
  { id: '2ec9c527-d437-4fbe-abbc-ef44dc0d975c', title: 'Mystery Woman: Sing Me a Murder', imdb_id: 'tt0433604' },
  { id: '2ca2568a-17bc-4a81-afee-94126bba74aa', title: 'Native Son', imdb_id: 'tt0042781' },
  { id: 'bf991376-86b2-4faa-a8be-6ff80eb33498', title: 'Night Chase', imdb_id: 'tt0066139' },
  { id: 'ec3a26c9-6f94-4d3c-a692-a8a547781899', title: 'Nina', imdb_id: 'tt0493076' },
  { id: '2f46f06a-ab91-4ed1-92c6-6040fcff17ed', title: 'Number One with a Bullet', imdb_id: 'tt0093658' },
  { id: 'ce844cf1-9a27-4542-86b7-6ecac3f6c3de', title: 'Playing with Fire', imdb_id: 'tt0089815' },
  { id: 'be20553e-04b2-4e63-b2da-a205ce53e962', title: 'Pressure Point', imdb_id: 'tt0056370' },
  { id: 'c25b7078-9376-428f-82a9-311b52f52e2d', title: 'Pressure Point', imdb_id: 'tt0056370' },
  { id: '18ee72c6-c617-48fa-ad65-8ba652bbbc3e', title: 'Queen', imdb_id: 'tt0105937' },
  { id: 'a3913f46-4265-43f6-8e55-a88b1986e025', title: 'Queen', imdb_id: 'tt0105937' },
  { id: '9ee7b08d-8bc8-410b-8a72-83e30c14b14a', title: 'Raid on Entebbe', imdb_id: 'tt0076594' },
  { id: 'ca7051aa-b035-4cfd-97c5-df3fe0a76876', title: 'Ransum Games', imdb_id: 'tt3331986' },
  { id: '649a99ad-aca6-44c5-bb55-a94d06b913e4', title: 'Ray Alexander: A Menu for Murder', imdb_id: 'tt0114239' },
  { id: '093bcecc-2c81-4583-bc5b-38cb7b64d982', title: 'Red Ball Express', imdb_id: 'tt0045072' },
  { id: 'eb99c043-215c-4f66-a614-89a303f64550', title: 'Red Ball Express', imdb_id: 'tt0045072' },
  { id: '31cac293-14eb-4293-901d-a84282232455', title: 'Rio Conchos', imdb_id: 'tt0058525' },
  { id: 'a0faf555-d6f9-41b0-99ae-fb1b71d7cd13', title: 'Roll of Thunder, Hear My Cry', imdb_id: 'tt0078173' },
  { id: 'f5375655-adb7-4257-8922-fe99e6808111', title: 'Samaritan: The Mitch Snyder Story', imdb_id: 'tt0091888' },
  { id: '9be2b5f1-bdb2-4750-9322-162be3763175', title: 'Separate But Equal', imdb_id: 'tt0102879' },
  { id: '2290a386-fbd2-468e-8291-8ae4ad62fb64', title: 'Separate But Equal', imdb_id: 'tt0102879' },
  { id: '61ff1b77-5363-4dba-91e1-da02109484d8', title: 'Separate But Equal', imdb_id: 'tt0102879' },
  { id: '99ec0209-c175-4883-898d-d16ee3c78328', title: 'Shoot to Kill', imdb_id: 'tt0096098' },
  { id: '426af269-e1ed-476b-81a1-751906e4a2f0', title: "Slaughter's Big Rip-Off", imdb_id: 'tt0070706' },
  { id: '5caf2ffa-f66d-43e7-8821-6b5173efd3cd', title: 'Something the Lord Made', imdb_id: 'tt0386792' },
  { id: '94a906e5-2488-4c38-9466-b39f714cca7f', title: 'Soul of the Game', imdb_id: 'tt0115631' },
  { id: '8b10dd1a-07cd-4c4f-a2ae-ae9efe889eb7', title: 'Steel Magnolias', imdb_id: 'tt2328749' },
  { id: 'f410cff9-26bb-4c0c-ae24-d9f38e76740c', title: "Stompin' at the Savoy", imdb_id: 'tt0105475' },
  { id: 'f0ba111c-66ec-4467-946f-adbd8fe88746', title: 'Streets of Gold', imdb_id: 'tt0092022' },
  { id: '89782ff3-2189-4975-b172-fe55d5be9993', title: 'Sucker Free City', imdb_id: 'tt0373280' },
  { id: '0791ad50-7ca9-4b07-b15c-94d1a897604c', title: 'Swordfish', imdb_id: 'tt0244244' },
  { id: 'fa666d10-020e-41f7-a7a3-b558bf601414', title: 'Take a Giant Step', imdb_id: 'tt0053331' },
  { id: '5b583603-846b-4347-a4ec-6ddfc3d4050e', title: 'Take a Giant Step', imdb_id: 'tt0053331' },
  { id: '24febcf7-4dee-4539-919f-31f1ef53040a', title: 'Teacher, Teacher', imdb_id: 'tt0065077' },
  { id: '8f026a9d-24af-477d-8fd4-564b0b209c7e', title: 'Tell Me That You Love Me, Junie Moon', imdb_id: 'tt0066445' },
  { id: '23c199df-bc0e-4cef-a859-d45edc699b1f', title: 'The Ambulance', imdb_id: 'tt0099026' },
  { id: '5d269614-e418-40c4-ae27-71293851d9ba', title: 'The Atlanta Child Murders', imdb_id: 'tt0088750' },
  { id: '07449849-d720-4771-b0fd-0def84a8f003', title: 'The Baron', imdb_id: 'tt0075729' },
  { id: '5dc6a92b-b65a-4849-b575-df87151406a9', title: 'The Brother from Another Planet', imdb_id: 'tt0087004' },
  { id: '158e5bda-b931-4377-96aa-aacbe657ce1c', title: 'The Brother from Another Planet', imdb_id: 'tt0087004' },
  { id: '9b2cf72f-b281-4896-b29b-bdf10532a5e5', title: 'The Cay', imdb_id: 'tt0246477' },
  { id: '57f60771-a8f6-4570-9105-9afed8c444cd', title: 'The Corner', imdb_id: 'tt0224853' },
  { id: '6c6bc7ef-ea8d-46f4-b367-8393b785524d', title: 'The Corner', imdb_id: 'tt0224853' },
  { id: '1a5113de-67fa-45d7-8fa5-34928a423489', title: 'The Corner', imdb_id: 'tt0224853' },
  { id: '55efb88f-1ec4-4247-8fbc-45f5e0517595', title: 'The Corner', imdb_id: 'tt0224853' },
  { id: '502568a8-9447-4ec7-892b-6aa456a8e976', title: 'The Corner', imdb_id: 'tt0224853' },
  { id: '40eb35ed-f94a-4418-a1b4-49e8ec22a6b2', title: 'The Corner', imdb_id: 'tt0224853' },
  { id: '9a6967ae-3599-415a-ade2-01dd0295e4d5', title: 'The Detonator', imdb_id: 'tt0345461' },
  { id: 'ebbb4be4-0921-4589-837d-aab64b16c2a8', title: 'The Displaced Person', imdb_id: 'tt0074413' },
  { id: 'd53149fc-6208-4838-81a0-e6f0838404c5', title: "The Ditchdigger's Daughters", imdb_id: 'tt0118989' },
  { id: 'd4ca1128-84a0-49d0-a018-84bdd961d0d9', title: 'The Enemy Within', imdb_id: 'tt0109730' },
  { id: 'b2243018-c563-41ca-83c4-0975138c4e34', title: 'The Ernest Green Story', imdb_id: 'tt0106826' },
  { id: '2a8b6613-6e98-43e8-af94-b8e951602330', title: 'The Exile', imdb_id: 'tt0021844' },
  { id: 'cb552dc1-8e02-4701-85a9-de91687b5375', title: 'The George McKenna Story', imdb_id: 'tt0091106' },
  { id: '07449c0d-3f10-4593-93cb-69287449f31f', title: 'The Greatest Thing That Almost Happened', imdb_id: 'tt0076110' },
  { id: '8ffb99a5-9c65-488a-9298-30de529344ad', title: 'The Green Pastures', imdb_id: 'tt0027700' },
  { id: 'd2ed6ab6-699c-497b-b0b1-4381e6d855bc', title: 'The Heart Is a Lonely Hunter', imdb_id: 'tt0063050' },
  { id: 'b1fda09f-0ebc-44c8-85e9-a60986202072', title: 'The Initiation of Sarah', imdb_id: 'tt0795403' },
  { id: '9de8bb1e-e26e-4b83-8b7b-d54c8b0c0ac7', title: 'The Inspectors 2: A Shred of Evidence', imdb_id: 'tt0239066' },
  { id: '968f0c7a-d008-4fb9-9ffc-af7c64957974', title: 'The Jericho Mile', imdb_id: 'tt0079366' },
  { id: '98554cba-3f52-4be4-a378-04fbb076a752', title: 'The Kid Who Loved Christmas', imdb_id: 'tt0099930' },
  { id: '65b21e1f-20f9-4945-b55b-e3261788b543', title: 'The Kid with the Broken Halo', imdb_id: 'tt0084202' },
  { id: '28951c50-7558-4009-92ee-63246c271794', title: 'The Learning Tree', imdb_id: 'tt0064579' },
  { id: '7b8cd384-ac5c-4712-b1ef-59bc408b8be1', title: 'The Liberation of L.B. Jones', imdb_id: 'tt0065979' },
  { id: 'eae56c9a-96b9-436e-b87e-6afee00216cc', title: 'The Liberation of L.B. Jones', imdb_id: 'tt0065979' },
  { id: '8b7cddb9-b3a1-452f-a8b3-d6038a4305a7', title: 'The Lockdown Hauntings', imdb_id: 'tt12764606' },
  { id: 'b19210bf-08ca-4c14-abe7-6cd8b3b6f356', title: 'The Man', imdb_id: 'tt0068912' },
  { id: '907ccc19-338e-4857-a8e4-c2ab5318e661', title: 'The Marva Collins Story', imdb_id: 'tt0082719' },
  { id: '6f31b007-40aa-4a6b-8ff5-72e58030f34a', title: 'The Marva Collins Story', imdb_id: 'tt0082719' },
  { id: 'f300cc4d-7123-4607-8241-0612bda88c1c', title: 'The Monkey Hu$tle', imdb_id: 'tt0076404' },
  { id: 'e590dff7-204c-4927-8f4d-70c56bb2c1c0', title: 'The Muthers', imdb_id: 'tt0074941' },
  { id: '28374e7a-8626-40f3-ad4c-6594e76f9960', title: 'The Rosa Parks Story', imdb_id: 'tt0293562' },
  { id: '060c8f77-bb81-44e8-811b-c067a8b87249', title: 'The Slams', imdb_id: 'tt0070704' },
  { id: 'c356e0f0-1d91-4100-9c36-1e49ec107fce', title: 'The Slams', imdb_id: 'tt0070704' },
  { id: 'b2361181-af5d-4cfc-a97c-027a012b6f61', title: 'The Thing with Two Heads', imdb_id: 'tt0069372' },
  { id: '1347debe-635f-4304-b963-036d87fd7306', title: 'The Trial of the Moke', imdb_id: 'tt0217105' },
  { id: 'b3ef53c9-247a-4c93-b059-f3d7947b93eb', title: 'Tick, Tick, Tick', imdb_id: 'tt0065360' },
  { id: '844270c6-1170-4eac-a07e-b8eef6e1ffeb', title: 'To All My Friends on Shore', imdb_id: 'tt0067858' },
  { id: '47f9b810-92da-42a1-9aef-d23f831ba110', title: 'Trick Baby', imdb_id: 'tt0070833' },
  { id: '542a4223-8902-4f3e-bc57-2c2cb7d8b895', title: "Uncle Tom's Cabin", imdb_id: 'tt0094213' },
  { id: '95fd27e7-6711-4088-bdfb-9c69589f787b', title: "Uncle Tom's Cabin", imdb_id: 'tt0094213' },
  { id: '3b44f2fd-1417-47c8-8c90-2c45148e21f5', title: 'Velvet Smooth', imdb_id: 'tt0195379' },
  { id: 'f7e6a1aa-99d6-44c9-802a-b370460beb64', title: 'Where the Truth Lies', imdb_id: 'tt0373450' },
  { id: '72ad4eb0-acc4-4240-af5c-e0befe11f392', title: 'Where the Truth Lies', imdb_id: 'tt0207944' },
  { id: 'a99d1297-ab2c-4197-880c-4f0a6bf7317c', title: 'Witness Protection', imdb_id: 'tt0191655' },
]

async function main() {
    console.log(`Restoring posters for ${MOVIES.length} movies...\n`)
    let done = 0, failed = 0

    // Cache results by IMDB ID to avoid redundant calls
    const posterCache = new Map()

    for (const movie of MOVIES) {
        const n = done + failed + 1
        process.stdout.write(`[${n}/${MOVIES.length}] ${movie.title}... `)

        // Use cached result if we already fetched this IMDB ID
        if (posterCache.has(movie.imdb_id)) {
            const cached = posterCache.get(movie.imdb_id)
            if (cached) {
                // Still need to update this specific movie record
                try {
                    await axios.post(
                        `${BACKEND_URL}/api/admin/movies/${movie.id}/enrich-manual-imdb`,
                        { imdbId: movie.imdb_id },
                        { headers, timeout: 30000 }
                    )
                    console.log(`✓ (cached)`)
                    done++
                } catch (e) {
                    console.log(`✗ ${e.response?.data?.error || e.message}`)
                    failed++
                }
            } else {
                console.log(`- no poster available`)
                done++
            }
            await sleep(200)
            continue
        }

        try {
            const res = await axios.post(
                `${BACKEND_URL}/api/admin/movies/${movie.id}/enrich-manual-imdb`,
                { imdbId: movie.imdb_id },
                { headers, timeout: 30000 }
            )
            const poster = res.data.movie?.poster_path
            posterCache.set(movie.imdb_id, poster || null)
            console.log(poster ? `✓` : `✓ (no poster)`)
            done++
        } catch (err) {
            posterCache.set(movie.imdb_id, null)
            console.log(`✗ ${err.response?.data?.error || err.message}`)
            failed++
        }
        await sleep(350)
    }

    console.log(`\n✅ Done: ${done} updated, ${failed} failed`)
}

main().catch(console.error)
