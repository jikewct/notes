
## compaction



        |Open：启动触发compaction
        |Get：seek触发compaction
        |MakeRoomForWrite: minor 确保可以写入mm中（如果不行，可能会出发compaction或者hang）
Next/Prev
    ParseKey
        |RecordReadSample 迭代顺序读取，每读取1M记录一个样本
    CompactRange: 手动触发compact
        |TEST_CompactRange
            MaybeScheduleCompaction: 如果当前没有安排后台compaction，并且当前需要compaction，则安排起来
                Schedule: 把BGWork(db)安排到后台线程执行。
                    BGWork
                        BackgroundCall: 调用compaction，并且吊起下一次compaction
                            BackgroundCompaction
                                PickCompaction
                                DoCompactionWork
                                    MakeInputIterator
                                CleanupCompaction
                                ReleaseInputs
                                DeleteObsoleteFiles
                            MaybeScheduleCompaction


MakeRoomForWrite:

- 如果上一次minor没有完成，然后又需要来一次minor的直接hang住等待
- 如果L0 sst数量达到soft limit(8)，minor等待且最多等待1s
- 如果L0 sst数量达到hard limit(12)，同样直接hang住等待

ShouldStopBefore:

OpenCompactionOutputFile:

FinishCompactionOutputFile:

InstallCompactionResults: 把compaction结果安装到日志中

compaction：

- 优先触发minor compaction


minor: 从imm到ldb

major: 从l到l+1

major.DoCompactionWork:


