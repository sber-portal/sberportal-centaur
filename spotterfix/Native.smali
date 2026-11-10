.class public final Lcom/anonym/bridge/Native;
.super Ljava/lang/Object;


# static fields
.field private static loaded:Z


# direct methods
.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static ensure()V
    .locals 2

    sget-boolean v0, Lcom/anonym/bridge/Native;->loaded:Z

    if-nez v0, :done

    :try_start_0
    const-string v0, "spotterfix"

    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V

    const/4 v0, 0x1

    sput-boolean v0, Lcom/anonym/bridge/Native;->loaded:Z

    const-string v0, "AliceBridge"

    const-string v1, "spotterfix loaded"

    invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    goto :done
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    move-exception v0

    const-string v1, "AliceBridge"

    invoke-virtual {v0}, Ljava/lang/Throwable;->toString()Ljava/lang/String;

    move-result-object v0

    invoke-static {v1, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I

    :done
    return-void
.end method
