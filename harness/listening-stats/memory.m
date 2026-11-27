// Build against the production SGPlayLog and SGLocalize as in build.sh.
// Usage: memory <private empty directory> <row count>. Run each size in a fresh process.
#import "Shared/ListeningStats/SGPlayLog.h"
#import "../harness-wait.h"
#import <mach/mach.h>
#import <malloc/malloc.h>
#import <sys/resource.h>

static int64_t footprint(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t size = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &size) != KERN_SUCCESS) exit(1);
    return info.phys_footprint;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSString *path = [@(argv[1]) stringByAppendingPathComponent:@"Listening.tsv"];
        int rows = atoi(argv[2]);
        FILE *file = fopen(path.fileSystemRepresentation, "wx");
        if (!file) return 1;
        for (int i = 0; i < rows; i++)
            fprintf(file, "%d\t180000\tspotify:track:%022d\tExample song %d\tExample artist %d\tExample album %d\t00000000-0000-4000-8000-%012x\n",
                    1700000000+i, i%5000, i%5000, i%500, i%1000, i);
        if (fclose(file)) return 1;
        malloc_statistics_t initial, final;
        malloc_zone_statistics(NULL, &initial);
        int64_t before = footprint();
        __attribute__((objc_precise_lifetime)) SGPlayLog *log = [[SGPlayLog alloc] initWithPath:path];
        __block BOOL loaded = NO;
        [log loadWithCompletion:^{ loaded = YES; }];
        HARNESS_AWAIT(loaded);
        @autoreleasepool {
            if (log.loadError || log.plays.count != rows) return 1;
        }
        // Publication precedes destruction of the worker's parser temporaries. Measure
        // the still-live log at rest, not that race; ru_maxrss retains the load peak.
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5]];
        struct rusage usage;
        if (getrusage(RUSAGE_SELF, &usage)) return 1;
        malloc_zone_statistics(NULL, &final);
        printf("%d rows: live heap %.1f B/play, footprint delta %.2f MiB, peak RSS %.2f MiB\n", rows,
               ((double)final.size_in_use - initial.size_in_use)/rows, (footprint()-before)/1048576., usage.ru_maxrss/1048576.);
    }
}
