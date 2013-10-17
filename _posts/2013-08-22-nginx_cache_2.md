---
layout: post
title: Squid源码分析(二)之替换策略
---


Squid源码分析(二)之替换策略
=====================


{% highlight c %}
void storeReplSetup(void)
{
	storeReplAdd("heap", createRemovalPolicy_heap);
	storeReplAdd("lru", createRemovalPolicy_lru);
}
{% endhighlight %}
目前squid2.7分为2大类： head基于堆的，LRU是基于双向链表

{% highlight c %}
/*
 * called to add another store removal policy module
 */
void
storeReplAdd(const char *type, REMOVALPOLICYCREATE * create)
{
    int i;
    /* find the number of currently known repl types */
    for (i = 0; storerepl_list && storerepl_list[i].typestr; i++) {
	assert(strcmp(storerepl_list[i].typestr, type) != 0);
    }
    /* add the new type */
    storerepl_list = xrealloc(storerepl_list, (i + 2) * sizeof(storerepl_entry_t));
    memset(&storerepl_list[i + 1], 0, sizeof(storerepl_entry_t));
    storerepl_list[i].typestr = type;
    storerepl_list[i].create = create;
}
{% endhighlight %}
我们看到一个非常重要的全局变量storerepl_list ，它存储了所有的替换策略信息。
{% highlight c %}
storerepl_list[i].create = create; 
{% endhighlight %}
调用关系如下：
main – > storeInit
{% highlight c %}
void
storeInit(void)
{
    storeKeyInit();
    storeInitHashValues();
    store_table = hash_create(storeKeyHashCmp,
	store_hash_buckets, storeKeyHashHash);
    mem_policy = createRemovalPolicy(Config.memPolicy);
    storeDigestInit();
    storeLogOpen();
    stackInit(&LateReleaseStack);
    eventAdd("storeLateRelease", storeLateRelease, NULL, 1.0, 1);
    storeDirInit();
    storeRebuildStart();
    cachemgrRegister("storedir",
	"Store Directory Stats",
	storeDirStats, 0, 1);
    cachemgrRegister("store_check_cachable_stats",
	"storeCheckCachable() Stats",
	storeCheckCachableStats, 0, 1);
    cachemgrRegister("store_io",
	"Store IO Interface Stats",
	storeIOStats, 0, 1);
}
{% endhighlight %}

{% highlight c %}
/*
 * Create a removal policy instance
 */
RemovalPolicy *
createRemovalPolicy(RemovalPolicySettings * settings)
{
    storerepl_entry_t *r;
    for (r = storerepl_list; r && r->typestr; r++) {
	if (strcmp(r->typestr, settings->type) == 0)
	    return r->create(settings->args);
    }
    debug(20, 1) ("ERROR: Unknown policy %s\n", settings->type);
    debug(20, 1) ("ERROR: Be sure to have set cache_replacement_policy\n");
    debug(20, 1) ("ERROR:   and memory_replacement_policy in squid.conf!\n");
    fatalf("ERROR: Unknown policy %s\n", settings->type);
    return NULL;		/* NOTREACHED */
}
{% endhighlight %}
根据前面的回调设置，即到下面的函数：
{% highlight c %}
RemovalPolicy *
createRemovalPolicy_lru(wordlist * args)
{
    RemovalPolicy *policy;
    LruPolicyData *lru_data;
    /* no arguments expected or understood */
    assert(!args);
    /* Initialize */
    if (!lru_node_pool)
	lru_node_pool = memPoolCreate("LRU policy node", sizeof(LruNode));
    /* Allocate the needed structures */
    lru_data = xcalloc(1, sizeof(*lru_data));
    policy = cbdataAlloc(RemovalPolicy);
    /* Initialize the URL data */
    lru_data->policy = policy;
    /* Populate the policy structure */
    policy->_type = "lru";
    policy->_data = lru_data;
    policy->Free = lru_free;
    policy->Add = lru_add;
    policy->Remove = lru_remove;
    policy->Referenced = lru_referenced;
    policy->Dereferenced = lru_referenced;
    policy->WalkInit = lru_walkInit;
    policy->PurgeInit = lru_purgeInit;
    policy->Stats = lru_stats;
    /* Increase policy usage count */
    nr_lru_policies += 0;
    return policy;
}
{% endhighlight %}
其中重要的是设置了该替换策略的各类回调函数
{% highlight c %}
    policy->_type = "lru";
    policy->_data = lru_data;
    policy->Free = lru_free;
    policy->Add = lru_add;
    policy->Remove = lru_remove;
    policy->Referenced = lru_referenced;
    policy->Dereferenced = lru_referenced;
    policy->WalkInit = lru_walkInit;
    policy->PurgeInit = lru_purgeInit;
    policy->Stats = lru_stats;
{% endhighlight %}
对应于下面的结构体：
{% highlight c %}
struct _RemovalPolicy {
    const char *_type;
    void *_data;
    void (*Free) (RemovalPolicy * policy);
    void (*Add) (RemovalPolicy * policy, StoreEntry * entry, RemovalPolicyNode * node);
    void (*Remove) (RemovalPolicy * policy, StoreEntry * entry, RemovalPolicyNode * node);
    void (*Referenced) (RemovalPolicy * policy, const StoreEntry * entry, RemovalPolicyNode * node);
    void (*Dereferenced) (RemovalPolicy * policy, const StoreEntry * entry, RemovalPolicyNode * node);
    RemovalPolicyWalker *(*WalkInit) (RemovalPolicy * policy);
    RemovalPurgeWalker *(*PurgeInit) (RemovalPolicy * policy, int max_scan);
    void (*Stats) (RemovalPolicy * policy, StoreEntry * entry);
};
{% endhighlight %}
LRU替换策略主要的方法类似 add一个新对象或者访问一个对象(Referenced) 等。

我们看看lru_referenced

其实很简单，就是被访问后加入到链表尾部
{% highlight c %}
static void
lru_referenced(RemovalPolicy * policy, const StoreEntry * entry,
    RemovalPolicyNode * node)
{
    LruPolicyData *lru = policy->_data;
    LruNode *lru_node = node->data;
    if (!lru_node)
	return;
    dlinkDelete(&lru_node->node, &lru->list);
    dlinkAddTail((void *) entry, &lru_node->node, &lru->list);
}
{% endhighlight %}
