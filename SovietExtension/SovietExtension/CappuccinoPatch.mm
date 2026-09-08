//
//  CappuccinoPatch.mm
//  SovietExtension
//
//  WeChat 4.x 的聊天 UI 由 Qt/mmui 绘制，AppKit 无法直接取得单个气泡视图。
//  本补丁在 wechat.dylib 加载后扫描 __DATA_CONST 中的主题颜色槽位，
//  通过写时复制修改当前进程内的颜色值，不改动磁盘上的微信文件。
//

#import "CappuccinoPatch.h"
#import "RevokePatch.h"

#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <string.h>
#import <unistd.h>

NSString * const YMCappuccinoThemeEnabledKey = @"kCappuccinoTheme.SOVIET";

#pragma mark - 颜色规则

/*
 微信 4.1.11 主题颜色槽位的稳定签名：
   [0..3]   小端 ARGB，即内存顺序 BB GG RR AA
   [4..7]   颜色资源关联值
   [8..34]  27 字节 0

 匹配时同时检查颜色、关联值和 27 字节零区，避免误修改普通代码或图片数据。
 新微信版本若更换了颜色或布局，只会匹配失败并写日志，不会按固定地址误写。
 */
typedef struct {
    const char *name;
    uint8_t signature[8];
    uint8_t replacement[4];
} YMCappuccinoColorRule;

static const YMCappuccinoColorRule kYMCappuccinoRules[] = {
    // 自己的气泡：正常、按下、悬停及内部浅色层。
    {"right bubble light",       {0x69, 0xEC, 0x95, 0xFF, 0x75, 0xB5, 0x3E, 0x00}, {0x82, 0xA8, 0xC8, 0xFF}}, // #95EC69 -> #C8A882
    {"right bubble pressed",     {0x63, 0xDF, 0x8D, 0xFF, 0x7C, 0xB8, 0x47, 0x00}, {0x70, 0x93, 0xB9, 0xFF}}, // #8DDF63 -> #B99370
    {"right bubble pressed deep",{0x5E, 0xD3, 0x85, 0xFF, 0x83, 0xBC, 0x51, 0x00}, {0x62, 0x87, 0xAD, 0xFF}}, // #85D35E -> #AD8762
    {"right bubble pale",        {0xAF, 0xF0, 0xC5, 0xFF, 0x22, 0x35, 0x12, 0x00}, {0xB4, 0xCB, 0xE0, 0xFF}}, // #C5F0AF -> #E0CBB4
    {"right bubble palest",      {0xD1, 0xF9, 0xDE, 0xFF, 0x22, 0x35, 0x12, 0x00}, {0xD3, 0xE2, 0xEF, 0xFF}}, // #DEF9D1 -> #EFE2D3
    {"right bubble highlight",   {0x87, 0xEF, 0xAA, 0xFF, 0x5D, 0x90, 0x31, 0x00}, {0x9A, 0xBA, 0xD5, 0xFF}}, // #AAEF87 -> #D5BA9A
    {"right bubble variant 1",   {0x60, 0xCF, 0x72, 0xFF, 0x5D, 0x90, 0x31, 0x00}, {0x67, 0x8D, 0xB1, 0xFF}}, // #72CF60 -> #B18D67
    {"right bubble variant 2",   {0x56, 0xB9, 0x66, 0xFF, 0x5D, 0x90, 0x31, 0x00}, {0x59, 0x7B, 0xA1, 0xFF}}, // #66B956 -> #A17B59
    {"right bubble variant 3",   {0x54, 0xBC, 0x77, 0xFF, 0x90, 0xC3, 0x64, 0x00}, {0x60, 0x82, 0xA7, 0xFF}}, // #77BC54 -> #A78260
    {"right bubble variant 4",   {0x70, 0xD3, 0x80, 0xFF, 0x53, 0x81, 0x2C, 0x00}, {0x6C, 0x91, 0xB5, 0xFF}}, // #80D370 -> #B5916C
    {"right bubble variant 5",   {0x90, 0xDD, 0x9C, 0xFF, 0x41, 0x65, 0x22, 0x00}, {0x82, 0xA6, 0xC7, 0xFF}}, // #9CDD90 -> #C7A682

    // 深色模式下自己的气泡及其关联绿色。
    {"right bubble dark",        {0x5C, 0x9C, 0x25, 0xFF, 0x75, 0xB5, 0x3E, 0x00}, {0x44, 0x60, 0x80, 0xFF}}, // #259C5C -> #806044
    {"right bubble dark pair",   {0x75, 0xB5, 0x3E, 0xFF, 0x5C, 0x9C, 0x25, 0x00}, {0x38, 0x50, 0x70, 0xFF}}, // #3EB575 -> #705038
    {"right bubble dark hover",  {0x94, 0xC6, 0x69, 0xFF, 0x48, 0x7A, 0x1D, 0x00}, {0x4C, 0x68, 0x88, 0xFF}}, // #69C694 -> #88684C

    // 对方气泡：灰白改为奶泡色；深色模式改为暖黑咖啡色。
    {"left bubble light",        {0xF7, 0xF7, 0xF7, 0xFF, 0x24, 0x24, 0x24, 0x00}, {0xE4, 0xED, 0xF4, 0xFF}}, // #F7F7F7 -> #F4EDE4
    {"left bubble dark",         {0x00, 0x00, 0x00, 0xFF, 0x24, 0x24, 0x24, 0x00}, {0x1A, 0x21, 0x2B, 0xFF}}, // #000000 -> #2B211A
};

static const size_t kYMThemeSlotZeroCount = 27;
static BOOL YMHasAppliedCappuccinoPatch = NO;
static BOOL YMHasRegisteredCappuccinoDyldCallback = NO;

#pragma mark - 设置

void YMRegisterCappuccinoThemeDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        YMCappuccinoThemeEnabledKey: @NO,
    }];
}

static BOOL YMCappuccinoThemeEnabled(void) {
    YMRegisterCappuccinoThemeDefaults();
    return [[NSUserDefaults standardUserDefaults] boolForKey:YMCappuccinoThemeEnabledKey];
}

#pragma mark - Mach-O / 内存写入

static BOOL YMIsTargetWeChatResourceDylib(const char *path) {
    if (!path) {
        return NO;
    }

    NSString *imagePath = [NSString stringWithUTF8String:path];
    if (imagePath.length == 0 || ![[imagePath lastPathComponent] isEqualToString:@"wechat.dylib"]) {
        return NO;
    }

    return [imagePath containsString:@"/WeChat.app/Contents/Resources/"];
}

static BOOL YMThemeSlotHasZeroTail(const uint8_t *slot, const uint8_t *end) {
    if (!slot || !end || slot + 8 + kYMThemeSlotZeroCount > end) {
        return NO;
    }

    for (size_t index = 0; index < kYMThemeSlotZeroCount; index++) {
        if (slot[8 + index] != 0) {
            return NO;
        }
    }

    return YES;
}

static BOOL YMPatchThemeColorAtAddress(uint8_t *address,
                                       const uint8_t replacement[4],
                                       const char *ruleName) {
    if (!address || !replacement) {
        return NO;
    }

    vm_size_t pageSize = (vm_size_t)getpagesize();
    vm_address_t patchAddress = (vm_address_t)(uintptr_t)address;
    vm_address_t pageStart = patchAddress & ~((vm_address_t)pageSize - 1);
    vm_size_t protectSize = pageSize;

    // dyld 可能已把 __DATA_CONST 从 LC_SEGMENT_64 声明的 RW 改为只读。
    // 写入前查询页面的实际权限，完成后按实际权限恢复。
    mach_vm_address_t regionAddress = (mach_vm_address_t)pageStart;
    mach_vm_size_t regionSize = 0;
    vm_region_basic_info_data_64_t regionInfo = {};
    mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t objectName = MACH_PORT_NULL;
    kern_return_t regionResult = mach_vm_region(mach_task_self(),
                                                &regionAddress,
                                                &regionSize,
                                                VM_REGION_BASIC_INFO_64,
                                                (vm_region_info_t)&regionInfo,
                                                &infoCount,
                                                &objectName);
    vm_prot_t originalProtection = regionResult == KERN_SUCCESS
        ? regionInfo.protection
        : VM_PROT_READ;

    if (objectName != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), objectName);
    }

    kern_return_t result = vm_protect(mach_task_self(),
                                      pageStart,
                                      protectSize,
                                      false,
                                      VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (result != KERN_SUCCESS) {
        YMLog(@"[Cappuccino] vm_protect RW|COPY failed: %s, address=%p, kr=%d",
              ruleName,
              address,
              result);
        return NO;
    }

    memcpy(address, replacement, 4);
    __sync_synchronize();

    kern_return_t restoreResult = vm_protect(mach_task_self(),
                                             pageStart,
                                             protectSize,
                                             false,
                                             originalProtection);
    if (restoreResult != KERN_SUCCESS) {
        YMLog(@"[Cappuccino] restore protection failed: %s, address=%p, kr=%d",
              ruleName,
              address,
              restoreResult);
    }

    return memcmp(address, replacement, 4) == 0;
}

static NSUInteger YMPatchCappuccinoRulesInRegion(uint8_t *regionStart,
                                                 size_t regionSize,
                                                 const char *segmentName) {
    if (!regionStart || regionSize < 8 + kYMThemeSlotZeroCount) {
        return 0;
    }

    NSUInteger patchedCount = 0;
    const uint8_t *regionEnd = regionStart + regionSize;
    const size_t ruleCount = sizeof(kYMCappuccinoRules) / sizeof(kYMCappuccinoRules[0]);

    for (size_t ruleIndex = 0; ruleIndex < ruleCount; ruleIndex++) {
        const YMCappuccinoColorRule *rule = &kYMCappuccinoRules[ruleIndex];
        uint8_t *cursor = regionStart;

        while ((const uint8_t *)cursor + 8 + kYMThemeSlotZeroCount <= regionEnd) {
            size_t remaining = (size_t)(regionEnd - (const uint8_t *)cursor);
            const void *candidate = memchr(cursor, rule->signature[0], remaining);
            if (!candidate) {
                break;
            }

            uint8_t *slot = (uint8_t *)candidate;
            if ((const uint8_t *)slot + 8 + kYMThemeSlotZeroCount <= regionEnd &&
                memcmp(slot, rule->signature, sizeof(rule->signature)) == 0 &&
                YMThemeSlotHasZeroTail(slot, regionEnd)) {
                if (YMPatchThemeColorAtAddress(slot,
                                               rule->replacement,
                                               rule->name)) {
                    patchedCount++;
                    YMLog(@"[Cappuccino] patched %s in %s at %p",
                          rule->name,
                          segmentName ?: "unknown",
                          slot);
                }
            }

            cursor = slot + 1;
        }
    }

    return patchedCount;
}

static NSUInteger YMPatchCappuccinoInImage(const struct mach_header *header,
                                           intptr_t vmaddrSlide) {
    if (!header || header->magic != MH_MAGIC_64) {
        return 0;
    }

    const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
    const uint8_t *commandCursor = (const uint8_t *)(header64 + 1);
    NSUInteger patchedCount = 0;

    for (uint32_t commandIndex = 0; commandIndex < header64->ncmds; commandIndex++) {
        const struct load_command *command = (const struct load_command *)commandCursor;
        if (command->cmdsize < sizeof(struct load_command)) {
            YMLog(@"[Cappuccino] invalid Mach-O load command size=%u", command->cmdsize);
            break;
        }

        if (command->cmd == LC_SEGMENT_64 &&
            command->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *segment =
                (const struct segment_command_64 *)commandCursor;

            // 主题表目前位于 __DATA_CONST；同时扫描其他 __DATA* 段以兼容后续微信版本。
            if (strncmp(segment->segname, "__DATA", 6) == 0 && segment->filesize > 0) {
                uintptr_t runtimeAddress = (uintptr_t)(segment->vmaddr + vmaddrSlide);
                patchedCount += YMPatchCappuccinoRulesInRegion(
                    (uint8_t *)runtimeAddress,
                    (size_t)segment->filesize,
                    segment->segname
                );
            }
        }

        commandCursor += command->cmdsize;
    }

    return patchedCount;
}

#pragma mark - dyld 入口

static void YMCappuccinoDyldImageAdded(const struct mach_header *header,
                                       intptr_t vmaddrSlide) {
    if (!YMCappuccinoThemeEnabled() || YMHasAppliedCappuccinoPatch) {
        return;
    }

    const char *imagePath = NULL;
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
        if (_dyld_get_image_header(imageIndex) == header) {
            imagePath = _dyld_get_image_name(imageIndex);
            break;
        }
    }

    if (!YMIsTargetWeChatResourceDylib(imagePath)) {
        return;
    }

    NSUInteger patchedCount = YMPatchCappuccinoInImage(header, vmaddrSlide);
    if (patchedCount > 0) {
        YMHasAppliedCappuccinoPatch = YES;
        YMLog(@"[Cappuccino] applied successfully, patched=%lu, image=%s",
              (unsigned long)patchedCount,
              imagePath);
    } else {
        YMLog(@"[Cappuccino] no supported theme slots found; WeChat may have updated. image=%s",
              imagePath);
    }
}

void YMInstallCappuccinoThemePatch(void) {
    YMRegisterCappuccinoThemeDefaults();

    if (!YMCappuccinoThemeEnabled()) {
        YMLog(@"[Cappuccino] disabled, skip");
        return;
    }

    if (YMHasRegisteredCappuccinoDyldCallback) {
        return;
    }

    YMHasRegisteredCappuccinoDyldCallback = YES;
    _dyld_register_func_for_add_image(YMCappuccinoDyldImageAdded);
    YMLog(@"[Cappuccino] dyld callback registered");
}

__attribute__((constructor))
static void YMCappuccinoPatchEntry(void) {
    @autoreleasepool {
        // 全局 Catppuccin 主题由安装脚本在微信启动前写入命名主题表。
        // 此处不再执行旧版运行时颜色签名补丁，避免覆盖新主题或命中无关颜色。
        YMRegisterCappuccinoThemeDefaults();
        YMLog(@"[Cappuccino] disk theme mode; legacy runtime patch disabled");
    }
}
