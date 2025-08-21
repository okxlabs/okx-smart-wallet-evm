// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "./Base.t.sol";
import "src/libraries/Errors.sol";
import {MockERC20} from "src/test/MockERC20.sol";
import {MockMaliciousERC20} from "src/test/MockMaliciousERC20.sol";

error ERC20InsufficientBalance(address, uint256, uint256);

event CallFailed(uint256 index, uint256 originalLength, bytes returnData);

interface IMaliciousToken {
    function getDrainingAttackHeight() external returns (uint256);

    function getLargeBlobAttackHeight() external returns (uint256);
}

contract SimulationTest is Base {
    MockERC20 usdc;
    MockMaliciousERC20 maliciousToken;

    uint256 GAS_DRAINING_ATTACK_OFFSET = 1;
    uint256 LARGE_BLOB_ATTACK_OFFSET = 2;

    address[512] recipients;

    uint256 MAX_DEAL = 13132800;

    function setUp() public override {
        super.setUp();
        recipients = [
            relayer,
            address(0x00000025e7beafc847f473354337bf5de058e369ad),
            address(0x000001380903374f485f84050abcd192506b522f7c),
            address(0x000002e81c77ebafd312a504cf33476877a368d900),
            address(0x000003999ff1d0d3de3aac265461893f6cdf05dab4),
            address(0x000004648699be7f5f0b8260928e8b83b44cae0c56),
            address(0x000005999cf023fb0b5b44645f2469196ec4aa8d09),
            address(0x000006d2c63cd8ab47eb2a0b6962c16a943d5328bd),
            address(0x00000760554e840cc3036ffa54fc847b8096221a5f),
            address(0x000008d95adb92873959fcff5f3ee09918e1d24622),
            address(0x000009e5d2392e057197ab902af959cd65c80ee428),
            address(0x00000af470f936cb3e3401bbf54273c6a241881dd9),
            address(0x00000b381e06d44ebf6f37f43890b19fcd0a6ed3e8),
            address(0x00000c7dc8dffe9046a9ba3a7ae8192b1ad44aa72b),
            address(0x00000dfbf427aeabc252895616cecf29796f71a7ee),
            address(0x00000e0c63a48d5b7ba8f74bcd4df35f3d95b6a5e0),
            address(0x00000fb2fd5e502ff02da1a5a8591776e3f344966a),
            address(0x0000101f8d31a45fd22764f47e3d2c28803926b8e5),
            address(0x000011a36e198c1e4c5cd435333255f03341e67ea1),
            address(0x000012f2f9c313b35b5acd5bd5f80c25d7f9acd148),
            address(0x0000136e2e4d0279b8be4bb91d256c54fea2938b73),
            address(0x00001465bde2d9632ee1e6eac0eb2387840d34b9a5),
            address(0x000015ab9c4ca65e0c192b3242a639c4dbed35f81c),
            address(0x000016e3c155087db5989942c88afc27de80347250),
            address(0x0000179e9e630452f06dc96092e13a106af72e5789),
            address(0x000018e3c9ccd6916b8679e3e27376c54d9853ffaf),
            address(0x0000191d286642bd22948dbd26e7d1def580b94e44),
            address(0x00001aa86b21800bec4a4420972f569b0f83cca12b),
            address(0x00001b74ff7a2557b20d883600bca92f53914c111b),
            address(0x00001c35cbb5ecfde9a27dc65c4bd1a88b4949f6ce),
            address(0x00001d2d8bfc98fabb09359ed3bae8da4da5719bdd),
            address(0x00001e45b40ea1e982df2e43d89908d51c7e1ed2bc),
            address(0x00001f0b44f9c1ebf7ae3067a983c4cbdc39563fc9),
            address(0x000020c869223189f62c0f72e5dd66a8a6764ea7aa),
            address(0x000021c233212e080c935337b643fc8a1f59bd832e),
            address(0x00002287a522953ac4be8b747d670b27c9049fd721),
            address(0x0000230a21499fbb5521159250355b3298dee15cf3),
            address(0x000024b4770ee763811b0c8ce98d21b55c19f09e86),
            address(0x000025da7b3fae66740a8bda109803131ba8024ed8),
            address(0x000026f97f6d0b9a23f414634449f2e8d0a5832427),
            address(0x0000273bb44a8e4c6d14d5f2141feecbd8c9ce898b),
            address(0x0000286c035ab4bcdbb5f76b62d2f4c2025534be01),
            address(0x0000294e58f1b9bad782417cf53fca0f92ae16771d),
            address(0x00002acba8177d41ec69953497bf7378f591a3ca24),
            address(0x00002b5da3d96eef0f5fb89cc69507259465820901),
            address(0x00002cedfb8de051d733b1a46dad746fee2f2bd734),
            address(0x00002d1c79d35bb9558f8a8d87f2c2a045316e772e),
            address(0x00002e9d80fbad668df9e3f24a68e0ec95aa8915af),
            address(0x00002fa3e1730c5956cd0a3448bff2010347ab827b),
            address(0x00003005fa305871e7b8dc1d55168d0ca6ddb093cb),
            address(0x0000316cdc55931ca246f8aeca29b5d64998179e1c),
            address(0x000032b49ba5184d441562a885b65f7680c6bfbf15),
            address(0x000033ef1416037a7626fd5f143cd19c9d9ca46f8a),
            address(0x0000347a26925f4c5be9f5b438dcd2515af69abbb6),
            address(0x000035727f838af7b4bd2fbf48c4d3fff845a7222e),
            address(0x0000363afe38dae592aa5594e8385bcb97f290829d),
            address(0x00003752f2e038b05e803a23e098d61457b588560f),
            address(0x0000388586ae720478dc333ddc29c5d9ed16232cf7),
            address(0x0000390138f926670375740686e92deeda3e588853),
            address(0x00003abd84189f785e23a5e581ba5932d7fc636c4c),
            address(0x00003b7c9c3e63727ce3aa1246f655885b3069b726),
            address(0x00003c5ee28727a2c94049c4a43e6646439d2e5496),
            address(0x00003d731ecb0b0e92c8d2a36f0b5d71e09819c8de),
            address(0x00003e16271c227ea22e021550a47fb10040db6eb1),
            address(0x00003f3c8f71621d9c6f8479928fe0e136ffeed9bd),
            address(0x00004081254c95d49ad4147c311d5ad8d9e59f62a8),
            address(0x000041b9e5e3bc04828208dc952ac3a21b4eee3adc),
            address(0x0000428885ca55b91d3e78cc66042d617b966f3e20),
            address(0x000043b54368f48efa845931547753b7cdce42740c),
            address(0x000044132346301bcf96b97e1746bbf02df69b0d04),
            address(0x000045bb2426b0053193f8854b3b0ea34f8e5f726b),
            address(0x0000469e3df554c79208d93c11c8951a47ac9c0ecc),
            address(0x000047cb83699cfca7898c165c2e1af9bcf45a3db5),
            address(0x0000487c0085e54a9c22b9e573755bb4c3cc0ea0d5),
            address(0x000049bc5c5b1792bd13332ed2e7a1aa613d95f04c),
            address(0x00004ac0e1c5cc7ddd4c5125189a8092789ddf3e7e),
            address(0x00004bc789f7893ee18b38c92f5d7bc24509364059),
            address(0x00004c5097dc0d36c01cac9546a3f4a410b6461576),
            address(0x00004d75bb068857c933f8eaaf9a4d505b7eccc329),
            address(0x00004e6a35a08f09b99dbfbed8064f0cf79c5f1ff1),
            address(0x00004f3cb53e880b49bf4ba435ea13ce3eb8284141),
            address(0x000050e53271d0dd9638c859e62d9c398dc5504075),
            address(0x000051239bc217ff3700927dfe6cefebf9cc22ea96),
            address(0x000052e7ae269a9554d2d4665772ce15415f74f4d9),
            address(0x000053da620060f88073f28504c5b9d5f24fcb7dc8),
            address(0x000054ac60eb50bbcf5a830464470f31d8e5a0f485),
            address(0x0000556e128f1b3c45372a415378cc0cb75c9b6183),
            address(0x000056b0053caffe9e9ad40a9f2c6d3b6415277676),
            address(0x00005762a3e91a9d831b9976f512bbc042455612e0),
            address(0x0000586325dd4bf573424d4816c7148f718a953ca4),
            address(0x000059dde8149db8b00294c167b824226d1cc0bd7c),
            address(0x00005ab3498742b627acfec51a8b0d54cef098f88f),
            address(0x00005b9548bbd8b23a20c36ec3f1293c45a9fa6b74),
            address(0x00005c81c0e9704303af17cce66c9f2618b1d0e934),
            address(0x00005d050a89a083b9687aac9114eacc891f197f0f),
            address(0x00005e9ef89e4f771f3700494022f44d9684db088f),
            address(0x00005f29a9c30eaf1a79f9732c0e0d894439947b3d),
            address(0x0000607248ce6e057c6df78fe36fad7177a62a3397),
            address(0x0000616a72da0ba5767b6fefd72679d4cca1373cb8),
            address(0x0000627ea53afaab72abef55eafb11ac02a8f75b47),
            address(0x000063865886fc52407532a6255c6d6625af85bd7a),
            address(0x0000648389308c71e586f546aff08bf0c927a457d4),
            address(0x000065436e7177fab4148f5666525f21e0fd859d80),
            address(0x000066abfed0845da9f934f111dd7e168c34fb7855),
            address(0x0000676c676111edaa9024e26179379429d8ff7a97),
            address(0x000068449c9e4be2c2d1303bbed10bc733d555441f),
            address(0x0000698e9b3e022c04b9623ce3b3f3e2088e2a70d1),
            address(0x00006a3d9689e03273350dd464ce0c7d963f744a07),
            address(0x00006bb83fa8aadd2bb2c9912be66b102cde8b6e07),
            address(0x00006c2d01961c6db0cbec472e90a6c870e75be9c4),
            address(0x00006d316e33dd77ebded2a88df8b0f2640d593175),
            address(0x00006ead0d4930caed29240e9b15cbe1e2f4c32726),
            address(0x00006f0b17ed8bc4aa04450fb0be9221a82374c341),
            address(0x00007088960c37a96435d75b3fb5cfe05834d48c8d),
            address(0x000071c7554863a143c739a3b699ddb5c1f8cdbad7),
            address(0x00007220a40b53da5e369267279b945c295620f8f9),
            address(0x000073d8d9e80acac23bab25c992ccd1cee331bb93),
            address(0x000074598568c3dbed81f0fd713c8bdf8055d7e976),
            address(0x0000759ff991653a72d145345a25cc425237e45a47),
            address(0x00007686b28e80db92b5391b5cd866fb402fa66d3d),
            address(0x0000772d08673518daeed96ba2f1246ffc07b927b7),
            address(0x00007845c2a32a17cd611b4f2b8ba0bfe6c229b232),
            address(0x00007986acb063fb333134237207c8c466c3205579),
            address(0x00007a9e9cbf86a9838695a430f8239778a44a2d1f),
            address(0x00007bf7b2fc242e4be40b27dbe73260c4c090e81b),
            address(0x00007c938de98292da198e882eb7e370dda76f1e06),
            address(0x00007dba23f9089e4f58ecdbdb40da6352c1ef46c7),
            address(0x00007e5603429cbe5e041018d5d77162f6bd5179bf),
            address(0x00007f1917ad10f41c52fbe11eb925d79060848e7a),
            address(0x00008066a5c4e5188caa7f3d614bec2e2aa659ba6c),
            address(0x0000815d506f95520e697a2aec6c52c45b1c20d51f),
            address(0x0000825e56d0c3c3cea23ded3b341e540e771a6821),
            address(0x0000836fe23a9e7fdbfd081c35e4414fea643ae77d),
            address(0x00008414c5a0b39802db119918d8f9ea0ff7b71dd6),
            address(0x000085d9924fd1d8cb398f1af9afcc81d77ac1a68d),
            address(0x0000860a6c575515ff60ba3b020ccd3387a9952442),
            address(0x0000877d8b4cd2fb4be72aeb599e5be7ebc266f3af),
            address(0x000088263494ee587f34366a8cce81e97afc6bc536),
            address(0x0000892916e14b264d4ed2e6c55739f102d443d484),
            address(0x00008a1d41b488dd66e028827dcdd50b1ac270180e),
            address(0x00008b3ee4559d7490f61017560662511efab42cc3),
            address(0x00008c85e61e386f79eee15d9afdd29b3689eb4fb9),
            address(0x00008d35ca283de635fbc4caab717c7574593835e8),
            address(0x00008e5086028a3f3322bc7061e3ad6a88402c66a8),
            address(0x00008f095b6e88412e75e344913b2d3758f726a00a),
            address(0x000090502b060325757aa0c8f649bb3b515f9dd4dc),
            address(0x000091776ef27fd18b022c144737d6583f544c5a5e),
            address(0x0000929448cc3b7ab94a4df40a238641d0f39f1558),
            address(0x0000939c7ea1aab0dd473887059a3dad08b98d6d86),
            address(0x00009498790b9b387f11683d00b0d0e89d2033cb70),
            address(0x0000955f9d0eaf415173fe10a7dc0abb2dd01ed308),
            address(0x0000961354124f152f32186193cb6ffbf88adf351a),
            address(0x000097ba2e9dd20de285f94bd00fd6ce1afd2f86bc),
            address(0x00009863c795760c152552d697761b7410bb8a82d3),
            address(0x000099e9b9bbc4d943c0d54ed385a832c17d96b623),
            address(0x00009a3b91d48636eec836bd6c4b4dd43adc7c0e7f),
            address(0x00009bf11d72c45c05625e20e6b849bad52d8bef09),
            address(0x00009c776552c6d7f027fb7f363d3ece3ab109f545),
            address(0x00009d995dca6b41f99981a567570bfe92938ec429),
            address(0x00009e1e6bc44225d75f86d027ac1bcd46467f84c7),
            address(0x00009f93c9c3fe17401c6cd3c6f29aacccb1068a47),
            address(0x0000a062bccb03924160c2a8e833ec52f3d6ff1d24),
            address(0x0000a1c93ed1f1c2051555b2f9134e99a8abf83248),
            address(0x0000a2ee62375f3c0245855188094ae6ff61639558),
            address(0x0000a30115ba26d51eff124caf12fd13d7fb9427fa),
            address(0x0000a4a7c81068f7a87f7d9219b47a8eedb5e74c3d),
            address(0x0000a5262004e0705a418b7ca06b844ea70350204c),
            address(0x0000a6ca0dc4b08ef1e0299912d80495556471b39b),
            address(0x0000a7d5827708bc7483e17f9823a5feef3f304d5a),
            address(0x0000a80b65e4d051989f4bddf96b78be2d2bf113c9),
            address(0x0000a9b15e5db719c983cc637bd0a5d0375e232187),
            address(0x0000aae1ef31e73e4c53e9f9af6acc7fbcba0f8bee),
            address(0x0000abd0f91cec34631513f2f0f6b4be760d7e350b),
            address(0x0000ac79e22205b163bd2aedae995605c0d1ed0aea),
            address(0x0000adb0bec69ce6f70a5138d7397229b8abadbb8b),
            address(0x0000ae77d22b3a400a2b0a10215215202751a40993),
            address(0x0000afa3ed80f9a0ae81da1414070b5af24c212dd2),
            address(0x0000b0f0729fd6d1d3bc00ea31d4374e58c12ebb23),
            address(0x0000b17e6c1d6a315b7c3513b2b860dd97adc57c72),
            address(0x0000b27f26906802acfde4a28be248426f41b0c6e7),
            address(0x0000b3917fda03870c5fa4f1b311e771e278aaefe4),
            address(0x0000b407fd13d75cd2b7b52564059f751782c7c8cb),
            address(0x0000b5a0367e9c306876232fe8066c3936b3536fab),
            address(0x0000b6458ec4664bb009fb52253ffee6addcaa248b),
            address(0x0000b71f62345ef10f02707b6ad29f5b4e52fac84a),
            address(0x0000b8fa6854728a7d45f60d9686945297646752a7),
            address(0x0000b9c969bd8ae597ad63298104a9b35292a45dd1),
            address(0x0000bafdcdd9c563f88a3b921a2ce5ec3bc0943303),
            address(0x0000bb8266e00dbd337c8f4a28afa6bbc3e388a4cd),
            address(0x0000bc074f94c6d2c4343e1b096d9616c2532980ce),
            address(0x0000bdeca0f9ec7cb5c3e51a6d5c3e2b790e9184fa),
            address(0x0000bec357ee50133543717a459fa9b06c22bb4ce5),
            address(0x0000bfdca639c2b2f74bcf82376cf95f5a6d4eb01d),
            address(0x0000c0e54806d7d88e8b706394c26acf96a48a97d7),
            address(0x0000c1c5690420730de7cd871060afd37953ba9734),
            address(0x0000c2438c9b3f9cf0e8ef846d17367a9ca4dc8780),
            address(0x0000c3b969b01d23334877cd84d33b0f3d233810ce),
            address(0x0000c4a4542e19b1efbbb9ecc6d2c63f84dd2a1028),
            address(0x0000c5747de57fa9094cfaa809d0605eb18997423e),
            address(0x0000c61c54c98c9c9a559420d107bfe78ea760ab14),
            address(0x0000c7f2e5f8f42878dae7b7249a21143852d21a12),
            address(0x0000c8ddd5556d670cacc529a511ec9cad1bd89c5e),
            address(0x0000c92b2705612099e4d1898385737b3f5a4bc11c),
            address(0x0000ca69f6a7dc101826ea64d254e409950dda34a6),
            address(0x0000cb353ac3257865ae5b202da5ccecaefe416ff8),
            address(0x0000ccde93965185d63cb55bdfd72f6bc913a83ebe),
            address(0x0000cdbf272160d218ec17df9c92c9ce7e88570e45),
            address(0x0000ce4c27c9ad48d0a59d24ef2204c541599839ec),
            address(0x0000cf7c50fbc7a5f63b5808936029c07c92866f2c),
            address(0x0000d05479b3220adaae10dd79cee4f279a2490446),
            address(0x0000d1805145a7289ef63d359b4362098b56653010),
            address(0x0000d2e72319d9bff083f8a3be355b5b7a0367a3b5),
            address(0x0000d3fa47e68eee9323e9eb023fbda67c772d1cae),
            address(0x0000d466312e1b8403a5731c0a56525469c1b3b3ad),
            address(0x0000d56a07469260ccf7d75999ae85f28f19746133),
            address(0x0000d6a95a593c90f6f3e1bf40c0bc209d0a95b1f6),
            address(0x0000d7ec47629ca85758b214691f0ef32d17b7a833),
            address(0x0000d88ab570843c7a9bffa957f99fdf8bd92e0dea),
            address(0x0000d9687b20be9174115039d79f02626726ceed5e),
            address(0x0000da874332bab458c89211b488cb2ef8f602d419),
            address(0x0000dbc0d7c459ebdc0257b72bae100dcd52591c8c),
            address(0x0000dcb2449e08dfaf178ceb7a16f7242b24668ae0),
            address(0x0000ddd116d314f27beb2a77a6e0a77dbcdf10c6b8),
            address(0x0000de02935800999d7e6217b1ad9e7ee1324239c5),
            address(0x0000df5e37dbd8036f50389dcdd1756f9b5d6534f5),
            address(0x0000e01afe5e9cc4cf9aedf1121934bf32c4d78e85),
            address(0x0000e145a5dd2ab9ec64e4650bbd3ca3172b039cd4),
            address(0x0000e2be2bde04a9f2961bd10194c131b24eec4c85),
            address(0x0000e34995447c6bdb5a9cc51cc3c1be32f8ab7bb8),
            address(0x0000e49bb1a7d4e8cfba9f29e0ecb54a571f7cc7a2),
            address(0x0000e58f6d10ea73a45db838d983dcd66246364ecc),
            address(0x0000e628481a83b4da3e0ca9a13fc1183eebe41909),
            address(0x0000e7f457cd65b06e7781d601436aeeedbacea585),
            address(0x0000e892e87011580cedb4f55bda13cd8230ce675f),
            address(0x0000e98cc1d17476428ff6d3c4fd786487fecd7b6a),
            address(0x0000eaeed7dfeb4308f3cf5c014b6650645498d36f),
            address(0x0000ebf8ab3f49145b5eaa813ed449dc2ec52c241e),
            address(0x0000ec0bf01d2c5e9367aec07456bf16d3b3c27649),
            address(0x0000ed8301c13d66cccd0c611ec913da0fbf85bc5f),
            address(0x0000ee9b04ce32d39deca0ce2c9ba2c972b5199dee),
            address(0x0000ef648d870629785bb55a3feb23cd49cb87d235),
            address(0x0000f090dec51377985118bd9cd5dcd3dd3021a309),
            address(0x0000f10379bcd11a9b32eb47478c31d29d9173f563),
            address(0x0000f237e40808d01971a2b9b7fa1f396e1b56eff0),
            address(0x0000f333631a4df71fcf00ef81df222f2622d485db),
            address(0x0000f4576a0e3691de094a8f4d6386d7159a3d93f1),
            address(0x0000f53c27681ce9fbecc9c2a1ddc4c33c48283d34),
            address(0x0000f6b25ef238242f64ce83b669702170470b30e3),
            address(0x0000f79a10dcbf77573bbd46592692562592d28768),
            address(0x0000f88ed01a2047aa413fcf6c78e681c9c897ccd8),
            address(0x0000f96655e57939766238560c0beee4f41dfcf49e),
            address(0x0000fa50b7f5e8277e49c2a22aa72e91a8c926285b),
            address(0x0000fb9fc186fb82aa6ef9ecaad8460144e1622d96),
            address(0x0000fc8aa9d5a1905ec58786ced3198340f9a1ccb2),
            address(0x0000fd40f26a4c1decbea5c28a1d6e01317e5bfb77),
            address(0x0000fe781d07be60496730fba1c84a17df84e600e5),
            address(0x0000ff52c145ff29c224cbbbc440253e3f744f42a7),
            address(0x0001004f7980ef0d64e8804d084be55490aca5afbe),
            address(0x000101cd02738865b1a00e79b0499a4d8107db900d),
            address(0x000102cb953014ecc5f78ce41595c2a66faa9c654c),
            address(0x00010381b425115391ec71e091e1a8623020b12dbc),
            address(0x00010455744b1bdafb670845be56b6f4f586326d61),
            address(0x00010577eb0de57bf481c84772627af2ad207c2d4b),
            address(0x0001065fac34cb93749d20850f007f06a1d6f528ce),
            address(0x000107a10575c74db4dcb5f8d75736d3a6f526380e),
            address(0x000108b79c1709cce577b54311a6cc25a0c34c2a43),
            address(0x00010968ddd522df1fc1a083e24b09e0f0efab0a67),
            address(0x00010a44b3db33ac52e59222a9edaaca90f54c8428),
            address(0x00010b2978beda5a87d6d4c79288ec6cf2d196ca66),
            address(0x00010cb17418ed529510aa667c198360025fd63754),
            address(0x00010d7dfb7a6854e2b717c3e6a577ce8e28734f71),
            address(0x00010ee021a6b55ee323ef2506bfa2d044b5278a2e),
            address(0x00010ff7241762faf428cb77d7e7bb66d2946707a1),
            address(0x000110d4b02113bfbe07b5838268d846ecde596ae8),
            address(0x00011130dee729fff34ec409126e65c778c30ad95a),
            address(0x000112ff458c5ab671fa5d9acebe46a4b06d53ebc8),
            address(0x000113e9bb30d1f533de949d8031df05f3e65040e3),
            address(0x00011477838987a5e40dfe9fba3961aee765290170),
            address(0x000115aee714398c851f81afdcf9bdd686909bec89),
            address(0x000116c77a95dac2268311020f9e396a976d189177),
            address(0x0001173e1b5569f2d191f6d3ed58699552e1b0d866),
            address(0x000118d3603a06cb5789ae014badf67c0c665b5e41),
            address(0x000119cb958114ac0ffeba88a71a0b45cbd1da1f55),
            address(0x00011a9708ac17b930b04742b9478db1e98004a4a2),
            address(0x00011bfd3deee2d5bc42ac1b97d970e7aa34a290b5),
            address(0x00011c456e4646a78cf42353ddb83dd0a88466058a),
            address(0x00011d160247a3330f1dc7a9cc2d1333740a799b6d),
            address(0x00011e1e0d754298c9a8242c589fba3339cf8f83b6),
            address(0x00011f1f47a2b188128d27ac01e85a992818d314a8),
            address(0x000120464a984fb6fb0ce93206fdd0f498eb02739c),
            address(0x000121d2ea60d41e8ddeeb83322c46e55920b983a2),
            address(0x00012212116bbddd63ef2b21bab0ca1826d7514e3b),
            address(0x0001233a4a6b56d5a87d59b7f43542125c249d7415),
            address(0x000124124ac48ff64aee55c0dce964a849ecd926d8),
            address(0x000125586f5e94af69fa32874f94a0d30a82a453a7),
            address(0x0001265f8d147f7d2f3f5a58966a80638d17ecb828),
            address(0x0001275936cb125558a9841d590922c3811390ee30),
            address(0x0001285e2ddf330f833797f8222491eded0039619f),
            address(0x000129f0cb1c0e8fb30e157ce41e0e76e8d4ce6061),
            address(0x00012a36e9c6b29c1c17eb66e646a07976e1ddd0d0),
            address(0x00012b1887334c085aa8f3c803141afeeb92ed6883),
            address(0x00012c30007209d81d8559702fc418aea87985c698),
            address(0x00012d60b01f01dd29191e6fdddea656d06d1a43c6),
            address(0x00012e291392e6375de22ce5fa725606fc98d1cec9),
            address(0x00012ff201b5351f8bfa760340a58e8c17b5405439),
            address(0x000130cda66fa400755d0effa3824d6a94bacba36a),
            address(0x00013100c13ac316f93385ededb00bb30bed0b851c),
            address(0x00013200d01bd1f33927e74bb03f5c5ddd1b76713e),
            address(0x0001334368d4f98b633c59bcc6885d76209c0c26fc),
            address(0x000134dd6491d59bf97856878949265b9a093f6d9f),
            address(0x00013590b73f9b8e10e1a48c9d9793a0b9159fbb44),
            address(0x000136a57628ebc60155216758ebaeaf0408d8d6fb),
            address(0x0001378ca6ebcff90da37c646f644ba79e77c19850),
            address(0x00013847065fc4129f17ad4bf20b760cd3593ac801),
            address(0x000139bf70871f4e749105dd45e65d81932e189e90),
            address(0x00013a7e96758fd15be38db032757a6dc6b03a3992),
            address(0x00013b74ba16c5b1e3b37d2bac26f7a4008d31732d),
            address(0x00013c7c7adfb39dd1d78517a99f5bd50ced1a2eb4),
            address(0x00013de795e2f4532b7bafbd51b513b6324235c4ad),
            address(0x00013ecabe9895c97e4fb055069f5d8e0b8490bc2b),
            address(0x00013fd12fc7de931d4bcc9dc34ebf77a946d35099),
            address(0x0001403f420c9dc1c58e30270738a34e3f7a6c2699),
            address(0x000141e7fde17fd76af96b4ee27854fa59fb559005),
            address(0x0001426b47d868a2e1f1d34c7f09c948d5bc8e6dda),
            address(0x0001439fa5b8a58451ebd84a16321542afa211ea73),
            address(0x0001445c0957c1619373f7365891d8e31463967ca0),
            address(0x0001451f95b3b2670e27afad8d36eedbc9a391f6ed),
            address(0x0001463e2a3b06eb9906fa92287fecdcf8389cfda7),
            address(0x00014725bd8545804e965010ac7336d9217245b080),
            address(0x000148e0e3b9791799728ea0b69c31c7cf4ffb879e),
            address(0x0001498c2a64c656da1637720736de0b4abf4cc1ad),
            address(0x00014a8a7596c87c4e11fb2052b7de1dbd464acf96),
            address(0x00014b889a093ac33afa97993d7676c3b8cce2d937),
            address(0x00014c0e7be3110b38f481886b5221b935ab4107e2),
            address(0x00014dd620ad46e2b8e08985241aa247fd176a5400),
            address(0x00014e89ce0a6d062538a1b13d475f90854fa08352),
            address(0x00014f7aed1cf924956f6e1f2f55df79b8771c49f5),
            address(0x000150dd5158fe177895ae0bd96b613270e0a1e817),
            address(0x0001516c94bab373d5cfa4be682174bdd30a237cd4),
            address(0x000152886d4a8124b6d3590e2675148468fb778c48),
            address(0x000153caa576a9a078f53f79ddaf8be887e21ed227),
            address(0x000154468b87844f31b2dc5edc370a5efb84fd8032),
            address(0x000155722ba7748483adfd09947f5b910d85a05898),
            address(0x000156dc45a5c8ccfa72a1063dd8350a231d089ef8),
            address(0x000157394cf1e8fbc4f1be64c00b14bca2d4f86a96),
            address(0x0001584e7c9a388ff108afbf3f9e79ce011c5740b4),
            address(0x00015932be2bf7c1ee802901f9d99a975f2d7912cc),
            address(0x00015af3a5e08bf4625277356f6c05e741384d0395),
            address(0x00015b12a2654a917ced3ba69634a449ac51cf7073),
            address(0x00015cc7abf5c874d94f869060e5760d627b9f2ba1),
            address(0x00015d80c4ff942a3168bfcae8cb1e9d42e52cd556),
            address(0x00015e92b69287956082c8c97605f8f8c9b625b031),
            address(0x00015ffb1ae18c658ca0cb21560438726adb3f7bdb),
            address(0x000160cb882c8ea43447e9dbec13d91cf97da9305f),
            address(0x0001615066a68626490b9e9ef18c626946d34d9291),
            address(0x000162e1ab3a9a89857350748d03ba3c49a6efc056),
            address(0x000163ac8c96a808adb21cb1aa59524cc431fbf83b),
            address(0x000164eb61a910216f883089d002caf49930c74507),
            address(0x000165713e1f811689f5630b84d48e8e356f11e268),
            address(0x0001664ecaa3f3baf32c421644b17e5555c917ba9d),
            address(0x00016761f14b69da063b7aff188edf6ca193cd9f94),
            address(0x000168994310f65a915a67c99cc951df355ed7aca0),
            address(0x000169d38b44a48511f1d0a4aa9e00fa57b845ced5),
            address(0x00016a1cd088c62472cf43100cf2f45aa371e1a638),
            address(0x00016ba9c2af3f4c3b4ee513b2937306787f3397d7),
            address(0x00016ca78d4ce29b0f83aff7bc7dccd76c3fefa73e),
            address(0x00016d7d40761796c062b542d80eac2306dfff64d3),
            address(0x00016e8d53b0b0e8af38df2a44900c24eba6506d6b),
            address(0x00016f4bc3ff207dafb6724c98b7105026551558d7),
            address(0x00017068e7be16f51f00767eacb4b2de837855aa67),
            address(0x00017142c5d67f5cb2e1349c347dc013cef2dc2260),
            address(0x0001722be10021e9af0d6e201143f2495e36ca127f),
            address(0x000173f5d03f299e639790a992949b54fe3d938f0c),
            address(0x000174c2b496d7e38898519044136b1e9070be960e),
            address(0x000175886784bc313f1ee3e6a166cf68beb6cdf13d),
            address(0x00017664556a84246a526b0ba9b79919de42f01156),
            address(0x000177f24a4e1f5db2a2db9b48ce78a068e940094b),
            address(0x0001784606aa5d20c43ab2cf3761c5643bf9b9af13),
            address(0x000179104ad4a656bf5d2d38255b285ce376d52d8b),
            address(0x00017a9664132a3a8ece10e328d8e3026dbd764c15),
            address(0x00017b1f78c33bfe7baa0267262dcecab4925a6786),
            address(0x00017c116a7f442539ff3b69deadd277e0a0fd30fe),
            address(0x00017d5a3ee9be65ab92a07819e04bbcc4c85f78a9),
            address(0x00017eeaf1d56d46e78c61c917c92a8909f54b2a98),
            address(0x00017f86f5102b1d20765f75c4e12b24c7ce4de99a),
            address(0x0001808d30e0f2077b3ef9d30bd29ee683799be2b2),
            address(0x0001816c442e3e0783aff271f5524d2659ff83e43d),
            address(0x0001827da4c76946c656af92f4c232e84e66cc64f9),
            address(0x00018399b0ec4caba330afd1679871340d2905f7e6),
            address(0x0001848553b110172e5d44501e5243e71d430e9cb0),
            address(0x0001859cfcc6068df3ec2599514c9e43c939bc9592),
            address(0x00018638d22d58f146d48f15c48cab3419fc5a587e),
            address(0x00018709d56bbeacbeb275a0a5692984435bd74c21),
            address(0x000188e93a049b281d786044f54fdb7bc86587cd95),
            address(0x0001899c574a51ed5154c5228b44472262133212f5),
            address(0x00018ae1b08ac0b1386a79b46ccecf02ce98fb21d9),
            address(0x00018bea5f129537ccbbb1f363353352c21e93db35),
            address(0x00018cd0d27e8e97b93cd8aeac010c25ed128f72b5),
            address(0x00018db4d34904766b413f0ff3a2ac228173e41568),
            address(0x00018e92eff2fb71a77a6e55a4c637a7103182281a),
            address(0x00018f6575bbf774c103dcbfa57e6760881ec72334),
            address(0x000190356668b138ef7d1f5fd446ec3ae5fd338f5c),
            address(0x000191a80f1ddf0abe8e815adf5c466fc9d4903600),
            address(0x000192d295a9ff3eef95d4a4d8525ff472eecf3cc7),
            address(0x000193ea4dab205fe7009b43e44f133aee87ffb1f6),
            address(0x000194fbb08d9bdeadc673ed6889af46b0b6d2bf07),
            address(0x0001955e089c7ea17226e25853e108593bc5834cba),
            address(0x0001969eec98faf657aec7879db561d11a7a54bcd0),
            address(0x0001979bd1c9f65a18793e6ae4ba6cfbc0c30bdb6d),
            address(0x000198ea9e4ce8d6c7ce8e124d4ea5df26f741393d),
            address(0x00019940289a23344edaa2cf2e59a08e166c7fa4bb),
            address(0x00019a5a7e4ad92339a795dfee4e4c84701fbf3b26),
            address(0x00019be9bfd7ac724bc110efb970497d196a6d329b),
            address(0x00019c01d127e80834efade45ccec21e87418b7a3a),
            address(0x00019d9f8b71b29aa95385671036212450e5738419),
            address(0x00019ed67ba56980ba9e172f166e85119b9b9d0840),
            address(0x00019f172f4e26db5b3172d387089af570fddc04c0),
            address(0x0001a0184cd3a20e0e8ed12b2f36558d810ef1717f),
            address(0x0001a1ff3aab29a981399825efe1532e73314552de),
            address(0x0001a28c706f4a2134fd5ea8c3eda9540d920fc5db),
            address(0x0001a334501318710f64de41a08fe0316b489d6da7),
            address(0x0001a456beacf46fb75529ff7c006924af376fb4e5),
            address(0x0001a5f33a0ba3c40831ca8a084ce713046944e3f6),
            address(0x0001a6e7cb08ef502a7aaa049ae6c55014cea99bf8),
            address(0x0001a72c69bbcdf71ff6a2b2a71acc4ec9246841d0),
            address(0x0001a80553ec3793415c73e3bab56d61108e1fcb10),
            address(0x0001a9b7ae9458ab436335bc3c3e992bc2d630ee13),
            address(0x0001aac9adf8e4c6ece02e142f921b3c48679cdb9a),
            address(0x0001abec799bcc1af34f7d67dbb276a306897f6133),
            address(0x0001acb7c8a30acf4390b28e8ffc713cbfbdce9f60),
            address(0x0001ad8bacc3ce20df94317a57880c8b8d523b7a30),
            address(0x0001ae997dcbf1eff444ab6a5b49b2ce657416674b),
            address(0x0001afa8bf1ffcc046d79b82cffacd8b7d916d89b7),
            address(0x0001b0b271d5dd132fe24147898ce9b2ffd841f753),
            address(0x0001b1d9a9e95ee30e4fc7a8b6d72f61f8cb1cbad8),
            address(0x0001b2726ed4b348ff8cd589e46689e10eef23e121),
            address(0x0001b35566b185d78f97f88259c613142e2091e829),
            address(0x0001b4ed2b0d82490b5643a55a7ab11c9f6b2c0c1d),
            address(0x0001b5a54ab29739938d2ff973c81e2244755dfbd4),
            address(0x0001b69059bac4997d10389a2a5466772c36ba7be1),
            address(0x0001b76721c8731f42b2bfe41b084b64f41f0ea7ad),
            address(0x0001b84f916f93026d898ad4156c1242d432a6759a),
            address(0x0001b9b0778d609f463e41f609acbc132ee1724f01),
            address(0x0001ba97cbc9704bd8914133c4655b21462221c225),
            address(0x0001bba77dcdb7fdfb8ce796d46d1aec695cc058bf),
            address(0x0001bc2cfcd3cd10dce375262c0364863d955f9187),
            address(0x0001bd6387a58e2a4330e73e1349fa7af0b52ffe6e),
            address(0x0001be629e19025e53fefa0be37527d87e459ad1c4),
            address(0x0001bfcbf26980753a692b560b8bcde069ac9cf5a3),
            address(0x0001c04cb87e7c00075bfc982be359f14c05ef0351),
            address(0x0001c1758ae4987cda81e480eb4abf252910209a2d),
            address(0x0001c2e6e1d1fb3fd7fe45367e79bacc6b661a7136),
            address(0x0001c3baddaf10eaa36f59373d79c575a4fce7cc7e),
            address(0x0001c4c60883747eab591ee714cfc4b94a10689a71),
            address(0x0001c59e328be156fee628e8c92df538d0ccf31f96),
            address(0x0001c6c07544bb5fa07c4c208ba02b6bdc161a2bc8),
            address(0x0001c73c52931d1c00fd24610d903bb11b2835964b),
            address(0x0001c85d3fbf7aa7908396ee1eed40ecdc46e423ba),
            address(0x0001c90b2a9692d97313168aa46ff110170566aaeb),
            address(0x0001ca7963e91e3ab6ba199df652c5962acf5fd051),
            address(0x0001cbbcf725210105cbc2466ac2e037f82a1a1fb3),
            address(0x0001cc93f426449fe005efda9b9f5abaffe34a908a),
            address(0x0001cdd82d225684798cab43fcdd24dadd4c6df9c6),
            address(0x0001ceb0475e21c2b1b2b2acccd0bbec76a8d9c52a),
            address(0x0001cf108f77caad56e6ddce447a99cc057d5f76ba),
            address(0x0001d00930a6cf52b7406590c87ec863bbfd3661a3),
            address(0x0001d1f1ac207b69a050cd6ee2325c43e8c909b624),
            address(0x0001d210c0d5e9b0ed7657541fe0d494c7c01835dd),
            address(0x0001d3b6be2bcff92590f111f3eab5a6dec3440e00),
            address(0x0001d4c51f37d693bb9303945b9c2edfa1e738c142),
            address(0x0001d59ab90bcfd678aacad4cd4543bddd8af32644),
            address(0x0001d665c34a8d4c598f1eb2f780fcf0d156ac40cd),
            address(0x0001d727d9213d3e7e73982eea83602cab3bb7b2d6),
            address(0x0001d811cf7928fa8bf7ee3d3d5978fee5347ae064),
            address(0x0001d910772382dd9787887376d6d28a56aa5b59c0),
            address(0x0001dac8171887d3c7c3f1468f6ebca6c022cfb08d),
            address(0x0001db4d9bcfaa9eacc7436f334a83a0d19626c74a),
            address(0x0001dca6dfa6bea896eac15a37b4c0054a6a6db355),
            address(0x0001ddb3d74d6ea8b52b7fe2d63c0193c2a22b8941),
            address(0x0001ded119934a912b7ce217295619004d60a8a19e),
            address(0x0001df5450a4fdebe6ee714c0d701df87fa71b41af),
            address(0x0001e0396824f393cf0b283f8c41ade48027ab55e3),
            address(0x0001e1226c6adcc55e3c7dadc8607d19d1fa8c9325),
            address(0x0001e289dd6dfe5b0f9a9337141b7271fbc509f78b),
            address(0x0001e3ab3a567cdebca5e30f9f05344ca8b8842c8e),
            address(0x0001e45ebfd416a02cb81117323cc64f6b7c4c8a00),
            address(0x0001e51756c1ea1459028ffb7ecf2b097ada2497a1),
            address(0x0001e6dc49eabfdd70c71267059b0f323011ebde0b),
            address(0x0001e77691e49cb31aa8c94f60926929efad6abcd6),
            address(0x0001e83adf13741af18481fbac129c52fd2e3e32be),
            address(0x0001e932c440d49f3e3a0e34bd5cfc377e096c7a1c),
            address(0x0001eaa0df7364134be2129df9fcba18193bab423b),
            address(0x0001eb146d5948815ae253905064e6366c74359777),
            address(0x0001eceaacdc0443816044cf1d05657be235175450),
            address(0x0001edf808658833aa0035f0e4b2bbd403dc9d925f),
            address(0x0001ee7d7d85b03efa8b039baff0782ac717bc6b71),
            address(0x0001ef2974dd18143af14121956d139abc13daa312),
            address(0x0001f080011f9889b9b70b0ad7e0018f171bb1b960),
            address(0x0001f1fc1db7ca5c4152d74bca032865e04955e2a6),
            address(0x0001f2fecdc15d08e54477067c3c238536a3755f16),
            address(0x0001f39557ed507085da8d2b83718653df7eaec759),
            address(0x0001f430e8a1003c34c6557fd47af796266c7932c0),
            address(0x0001f576b6e0b0628ae457abefc23c09ce96f89007),
            address(0x0001f613cb9efdf654d2b5cee5b4d8678c70163324),
            address(0x0001f7dea016bfec9f2d3d82d5ba70c5b743f1a5cb),
            address(0x0001f86855ca90338144b5d76c90746a13253ff7a6),
            address(0x0001f99885ac64298ac1cf00ff6bbb977381b6df50),
            address(0x0001faf6e63517618cf490ea6ab4d5f78aa477e5bd),
            address(0x0001fb1da51e2a6f171b9fdb3ad1317b3d75221cb5),
            address(0x0001fc315674c40cd497de4250ff12a3702c3e5256),
            address(0x0001fd5b1db6ef7a9e82e1b0b7e6bbc373e9d2a156),
            address(0x0001fedbc4e18d2f2ecc1b3a8b84c85a871bb2b2a1)
        ];

        usdc = new MockERC20();
        deal(address(usdc), _alice, MAX_DEAL);

        maliciousToken = new MockMaliciousERC20(
            block.number + GAS_DRAINING_ATTACK_OFFSET,
            block.number + LARGE_BLOB_ATTACK_OFFSET
        );
        deal(address(maliciousToken), _alice, MAX_DEAL);

        Call[] memory tempCalls = _construct_relayer_call(1, usdc);
        // Clear existing storage array
        delete relayerCalls;
        // Push elements individually
        for (uint i = 0; i < tempCalls.length; i++) {
            relayerCalls.push(tempCalls[i]);
        }
    }

    function _construct_usdc_batchcall(
        uint256 len
    ) private view returns (Call[] memory calls) {
        require(len <= recipients.length);
        calls = new Call[](len);
        for (uint256 i; i < len; i++) {
            calls[i] = _construct_erc20_transfer_call(
                usdc,
                recipients[i],
                (i + 1) * 100
            );
        }
    }

    function _construct_invalid_usdc_batchcall(
        uint256 len
    ) private view returns (Call[] memory calls) {
        require(len <= recipients.length);
        calls = new Call[](len);
        for (uint256 i; i < len; i++) {
            uint256 value = (i + 1) * 100;
            if (i == len - 1) {
                value = MAX_DEAL + 1; // exceed the max minted amount
            }
            calls[i] = _construct_erc20_transfer_call(
                usdc,
                recipients[i],
                value
            );
        }
    }

    function _construct_malicious_batchcall(
        uint256 len
    ) private view returns (Call[] memory calls) {
        require(len <= recipients.length);
        calls = new Call[](len);
        for (uint256 i; i < len; i++) {
            IERC20 token = usdc;
            if (i == len - 1) {
                token = maliciousToken;
            }
            calls[i] = _construct_erc20_transfer_call(
                token,
                recipients[i],
                (i + 1) * 100
            );
        }
    }

    function _decodeCallFailed(
        bytes memory errorData
    )
        private
        pure
        returns (uint256 index, uint256 originalLength, bytes memory returnData)
    {
        bytes4 selector;
        assembly {
            selector := mload(add(errorData, 32))
        }
        assertEq(selector, Errors.CallFailed.selector);

        // decode gas and error msg
        uint256 argsLen = errorData.length - 4;
        bytes memory payload = new bytes(argsLen);
        for (uint256 i = 0; i < argsLen; i++) {
            payload[i] = errorData[i + 4];
        }
        (index, originalLength, returnData) = abi.decode(
            payload,
            (uint256, uint256, bytes)
        );
    }

    function test_simulate_executeFromRelayer() public {
        Call[] memory calls = _construct_calls_data();

        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );

        vm.prank(relayer);
        uint256 gasStart = gasleft();
        try
            ISmartWallet(_alice).simulateExecuteWithRelayer(
                BatchedCall({calls: calls, nonce: 0, expiry: 0}),
                validatorData
            )
        {
            revert("should not reach here");
        } catch (bytes memory simulationResult) {
            // Check that it's the expected SimulateExecution error (now parameterless)
            bytes4 selector;
            assembly {
                selector := mload(add(simulationResult, 32))
            }
            assertEq(
                selector,
                Errors.SimulateExecution.selector,
                "Expected SimulateExecution error"
            );

            console.log("Simulation completed successfully");
            console.log(
                "Note: Gas breakdown no longer available from simulation"
            );
        }
        uint256 gasEnd = gasleft();
        console.log("gas used", gasStart - gasEnd);
    }

    function test_compareGas_simulateVsActual_executeFromRelayer() public {
        // Register validator first (required for both simulate and execute)
        _addValidator(_alice);

        // Setup common data for both tests
        Call[] memory calls = _construct_calls_data();
        bytes32 hash = _getValidationTypedHash(_alice, calls);
        bytes memory validatorData = _construct_validatorData(
            _alice,
            _alicePk,
            hash
        );
        BatchedCall memory batchedCall = BatchedCall({
            calls: calls,
            nonce: 0,
            expiry: 0
        });

        // Test 1: Measure gas for simulateExecuteWithRelayer
        uint256 simulateGasUsed;

        vm.prank(relayer);
        uint256 gasStart = gasleft();
        try
            ISmartWallet(_alice).simulateExecuteWithRelayer(
                batchedCall,
                validatorData
            )
        {
            revert("Simulation should always revert");
        } catch (bytes memory simulationResult) {
            uint256 gasUsedInSimulation = gasleft();
            simulateGasUsed = gasStart - gasUsedInSimulation;

            // Check that it's the expected SimulateExecution error (now parameterless)
            bytes4 selector;
            assembly {
                selector := mload(add(simulationResult, 32))
            }
            assertEq(
                selector,
                Errors.SimulateExecution.selector,
                "Expected SimulateExecution error"
            );

            // No more gas data is returned from the simulation - just the fact that it executed
        }

        // Test 2: Measure gas for actual executeWithRelayer
        uint256 actualGasUsed;

        vm.prank(relayer);
        gasStart = gasleft();
        ISmartWallet(_alice).executeWithRelayer(batchedCall, validatorData);
        uint256 gasEnd = gasleft();
        actualGasUsed = gasStart - gasEnd;

        // Log results for comparison
        console.log("=== GAS USAGE COMPARISON ===");
        console.log("Simulate gas used (total call):", simulateGasUsed);
        console.log("Actual execution gas used:", actualGasUsed);
        console.log(
            "Note: Simulation no longer returns internal gas breakdown"
        );

        // Calculate differences
        if (actualGasUsed > simulateGasUsed) {
            console.log(
                "Actual uses MORE gas by:",
                actualGasUsed - simulateGasUsed
            );
            console.log(
                "Difference percentage:",
                ((actualGasUsed - simulateGasUsed) * 100) / simulateGasUsed
            );
        } else {
            console.log(
                "Simulate uses MORE gas by:",
                simulateGasUsed - actualGasUsed
            );
            console.log(
                "Difference percentage:",
                ((simulateGasUsed - actualGasUsed) * 100) / actualGasUsed
            );
        }

        // Assert both operations completed (basic sanity check)
        assertTrue(simulateGasUsed > 0, "Simulation should consume gas");
        assertTrue(actualGasUsed > 0, "Actual execution should consume gas");

        // The actual execution should generally use similar or slightly different gas
        // This is more of an informational test than a strict assertion
        console.log("Test completed successfully - check gas comparison above");
    }
}
