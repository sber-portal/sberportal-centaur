.class public final Lyw/e;
.super Ljava/lang/Object;
.source "SourceFile"

# interfaces
.implements Lyw/a$a;


# instance fields
.field public final a:Lru/yandex/io/sdk/jni/AudioSource;

.field public final b:Lyw/d;

.field public final c:Lyw/h;

.field public final d:Lyw/g;

.field public final e:Ljava/util/concurrent/ConcurrentHashMap;
    .annotation system Ldalvik/annotation/Signature;
        value = {
            "Ljava/util/concurrent/ConcurrentHashMap<",
            "Ljava/lang/Integer;",
            "Ljava/lang/Boolean;",
            ">;"
        }
    .end annotation
.end field


# direct methods
.method public constructor <init>(Lru/yandex/io/sdk/jni/AudioSource;Lyw/d;Lyw/h;Lyw/g;)V
    .locals 0

    .line 1
    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    .line 2
    .line 3
    .line 4
    iput-object p1, p0, Lyw/e;->a:Lru/yandex/io/sdk/jni/AudioSource;

    .line 5
    .line 6
    iput-object p2, p0, Lyw/e;->b:Lyw/d;

    .line 7
    .line 8
    iput-object p3, p0, Lyw/e;->c:Lyw/h;

    .line 9
    .line 10
    iput-object p4, p0, Lyw/e;->d:Lyw/g;

    .line 11
    .line 12
    new-instance p1, Ljava/util/concurrent/ConcurrentHashMap;

    .line 13
    .line 14
    invoke-direct {p1}, Ljava/util/concurrent/ConcurrentHashMap;-><init>()V

    .line 15
    .line 16
    .line 17
    iput-object p1, p0, Lyw/e;->e:Ljava/util/concurrent/ConcurrentHashMap;

    .line 18
    .line 19
    return-void
.end method


# virtual methods
.method public final a(Ljava/lang/Exception;)V
    .locals 1

    iget-object v0, p0, Lyw/e;->b:Lyw/d;

    if-eqz v0, :cond_0

    invoke-interface {v0, p1}, Lyw/d;->c(Ljava/lang/Exception;)V

    :cond_0
    return-void
.end method

.method public final b(Ljava/nio/ByteBuffer;Lyw/f;I)V
    .locals 2

    .line 1
    const-string v0, "audioInputConfiguration"

    .line 2
    .line 3
    invoke-static {p2, v0}, Lkotlin/jvm/internal/j;->g(Ljava/lang/Object;Ljava/lang/String;)V

    .line 4
    .line 5
    .line 6
    iget-object v0, p0, Lyw/e;->e:Ljava/util/concurrent/ConcurrentHashMap;

    .line 7
    .line 8
    invoke-virtual {v0}, Ljava/util/concurrent/ConcurrentHashMap;->keySet()Ljava/util/Set;

    .line 9
    .line 10
    .line 11
    move-result-object v0

    .line 12
    invoke-static {p3}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    .line 13
    .line 14
    .line 15
    move-result-object v1

    .line 16
    invoke-interface {v0, v1}, Ljava/util/Set;->contains(Ljava/lang/Object;)Z

    .line 17
    .line 18
    .line 19
    move-result v0

    .line 20
    if-eqz v0, :cond_0

    .line 21
    .line 22
    return-void

    .line 23
    :cond_0
    iget-object v0, p0, Lyw/e;->b:Lyw/d;

    .line 24
    .line 25
    if-eqz v0, :cond_1

    .line 26
    .line 27
    invoke-interface {v0}, Lyw/d;->b()V

    .line 28
    .line 29
    .line 30
    :cond_1
    iget-object v0, p0, Lyw/e;->c:Lyw/h;

    .line 31
    .line 32
    iget-object v0, v0, Lyw/h;->a:Ljava/util/concurrent/ConcurrentHashMap;

    .line 33
    .line 34
    invoke-static {p3}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;

    .line 35
    .line 36
    .line 37
    move-result-object p3

    .line 38
    invoke-virtual {v0, p3}, Ljava/util/concurrent/ConcurrentHashMap;->get(Ljava/lang/Object;)Ljava/lang/Object;

    .line 39
    .line 40
    .line 41
    move-result-object p3

    .line 42
    check-cast p3, Ljava/util/List;

    .line 43
    .line 44
    if-nez p3, :make_default

    goto :cond_2

    :make_default
    new-instance p3, Ljava/util/ArrayList;

    invoke-direct {p3}, Ljava/util/ArrayList;-><init>()V

    sget-object v0, Lvoicetech/ChannelTypes$AudioInputChannelType;->RAW_MIC:Lvoicetech/ChannelTypes$AudioInputChannelType;

    invoke-interface {p3, v0}, Ljava/util/List;->add(Ljava/lang/Object;)Z

    .line 47
    .line 48
    :cond_2
    iget-object v0, p0, Lyw/e;->d:Lyw/g;

    .line 49
    .line 50
    invoke-interface {v0}, Lyw/g;->a()Lyw/i;

    .line 51
    .line 52
    .line 53
    move-result-object v0

    .line 54
    invoke-virtual {v0, p1, p2, p3}, Lyw/i;->a(Ljava/nio/ByteBuffer;Lyw/f;Ljava/util/List;)Ljava/util/ArrayList;

    .line 55
    .line 56
    .line 57
    move-result-object p1

    .line 58
    iget-object p2, p0, Lyw/e;->a:Lru/yandex/io/sdk/jni/AudioSource;

    .line 59
    .line 60
    invoke-virtual {p2, p1}, Lru/yandex/io/sdk/jni/AudioSource;->pushAudioData(Ljava/util/List;)V

    .line 61
    .line 62
    .line 63
    return-void
.end method

.method public final c(ILandroid/media/AudioRecord;Z)V
    .locals 0

    .line 1
    iget-object p1, p0, Lyw/e;->b:Lyw/d;

    .line 2
    .line 3
    if-eqz p1, :cond_0

    .line 4
    .line 5
    invoke-interface {p1, p2, p3}, Lyw/d;->a(Landroid/media/AudioRecord;Z)V

    .line 6
    .line 7
    .line 8
    :cond_0
    new-instance p1, Lyw/m;

    .line 9
    .line 10
    invoke-direct {p1}, Lyw/m;-><init>()V

    .line 11
    .line 12
    .line 13
    iget-object p2, p0, Lyw/e;->a:Lru/yandex/io/sdk/jni/AudioSource;

    .line 14
    .line 15
    invoke-virtual {p2, p1}, Lru/yandex/io/sdk/jni/AudioSource;->changeVqeInfo(Lyw/m;)V

    .line 16
    .line 17
    .line 18
    return-void
.end method
