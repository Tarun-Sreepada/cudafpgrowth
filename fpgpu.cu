#include <stdio.h>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <algorithm>
#include <map>
#include <chrono>
// nvcc -rdc=true .\rewrite.cu -lcudadevrt -o rewrite
// .\rewrite.exe transactional_T10I4D10K.csv 10 a.txt
// output 504
__device__ int patCount = 0;

struct TreeNode
{
    int item;
    int count;
    int childrenCount;

    // parent node
    TreeNode *parent;
    TreeNode **children;

    // __host__ __device__ TreeNode(int item, int count, TreeNode *parent)
    // __host__ __device__ ~TreeNode()
    // __host__ __device__ void addChild(int item, int count, int &location)
};

struct KV
{
    int item;
    TreeNode **itemLocations;
    int itemLocationsCount;

    // __host__ __device__ KV(int item, TreeNode *itemLocation)
    // __host__ __device__ ~KV()
    // __host__ __device__ void addItemLocation(TreeNode *itemLocation)
};

struct dMap
{
    int numOfItems;
    KV **keyVal;

    // __host__ __device__ dMap()
    // __host__ __device__ ~dMap()
    // __host__ __device__ int find(int item)
    // __host__ __device__ void add(TreeNode *itemLocation)
};

__device__ TreeNode *makeNode(int item, int count, TreeNode *parent)
{
    TreeNode *node = (TreeNode *)malloc(sizeof(TreeNode));
    node->item = item;
    node->count = count;
    node->parent = parent;
    node->childrenCount = 0;
    node->children = (TreeNode **)malloc(sizeof(TreeNode *) * count);
    return node;
}

__device__ dMap *makeMap()
{
    dMap *map = (dMap *)malloc(sizeof(dMap));
    map->numOfItems = 0;
    map->keyVal = (KV **)malloc(sizeof(KV *) * map->numOfItems);
    return map;
}

__device__ int findItem(dMap *map, int item)
{
    for (int i = 0; i < map->numOfItems; i++)
    {
        if (map->keyVal[i]->item == item)
        {
            return i;
        }
    }
    return -1;
}

__device__ void addNodeToKV(KV *keyVal, TreeNode *node)
{
    TreeNode **itemLocations = (TreeNode **)malloc(sizeof(TreeNode *) * keyVal->itemLocationsCount+1);
    for (int i = 0; i < keyVal->itemLocationsCount; i++)
    {
        itemLocations[i] = keyVal->itemLocations[i];
    }
    itemLocations[keyVal->itemLocationsCount] = node;
    keyVal->itemLocationsCount++;
    keyVal->itemLocations = itemLocations;
}

__device__ void addItemMap(dMap *map, TreeNode *node)
{
    // if item is not in map, add it
    int itemIndex = findItem(map, node->item);
    if (itemIndex == -1)
    {
        // new map
        KV **newKeyVal = (KV **)malloc(sizeof(KV *) * (map->numOfItems + 1));
        for (int i = 0; i < map->numOfItems; i++)
        {
            newKeyVal[i] = map->keyVal[i];
        }
        newKeyVal[map->numOfItems] = (KV *)malloc(sizeof(KV));
        newKeyVal[map->numOfItems]->item = node->item;
        newKeyVal[map->numOfItems]->itemLocationsCount = 1;
        newKeyVal[map->numOfItems]->itemLocations = (TreeNode **)malloc(sizeof(TreeNode *) * 1);
        newKeyVal[map->numOfItems]->itemLocations[0] = node;
        map->numOfItems++;
        map->keyVal = newKeyVal;
    }
    else
    {
        // add node to existing map
        addNodeToKV(map->keyVal[itemIndex], node);
    }

}

__device__ int *getPath(TreeNode *node)
{
    int nodes = 1;
    int *path = (int *)malloc(sizeof(int) * nodes);
    path[0] = nodes - 1;
    while (node->parent->item != -1)
    {
        nodes++;
        int *temp = (int *)malloc(sizeof(int) * nodes);
        for (int i = 0; i < nodes - 1; i++)
        {
            temp[i] = path[i];
        }
        temp[nodes - 1] = node->parent->item;
        path = temp;
        node = node->parent;
    }
    // printf("%d\n", nodes);
    path[0] = nodes - 1;

    return path;
}

__device__ void addChild(TreeNode *node, int item, int count, int &location, dMap *top)
{
    if (node->childrenCount == 0)
    {
        node->childrenCount = 1;
        TreeNode *child = makeNode(item, count, node);
        node->children = (TreeNode **)malloc(sizeof(TreeNode *) * count);
        node->children[0] = child;
        location = 0;
        addItemMap(top, child);
        return;
    }
    else
    {
        for (int i = 0; i < node->childrenCount; i++)
        {
            if (node->children[i]->item == item)
            {
                node->children[i]->count += count;
                location = i;
                return;
            }
        }
        node->childrenCount++;
        TreeNode *child = makeNode(item, count, node);
        TreeNode **newChildren = (TreeNode **)malloc(sizeof(TreeNode *) * node->childrenCount);
        for (int i = 0; i < node->childrenCount - 1; i++)
        {
            newChildren[i] = node->children[i];
        }
        newChildren[node->childrenCount - 1] = child;
        node->children = newChildren;
        location = node->childrenCount - 1;
        addItemMap(top, child);
        return;
    }
    return;
}

__global__ void partialMinerInitialize(dMap *map, int minSup);

__device__ void partialMiner(KV *keyVal, int minSup)
{
    // printf("Item: %d, depth: %d\n", keyVal->item, depth);
    dMap *map = makeMap();
    TreeNode *root = makeNode(-1,0,NULL);
    for (int i = 0; i < keyVal->itemLocationsCount; i++)
    {
        TreeNode *node = keyVal->itemLocations[i];
        TreeNode *partial = root;
        int location = -1;
        int *path = getPath(node);
        // printf("Nodes in path: %d", path[0]);
        for (int j = 0; j < path[0]; j++)
        {
            int item = path[j + 1];
            // printf("%d ", item);
            addChild(partial, item, node->count, location, map);
            partial = partial->children[location];
        }
        // printf("\n");
    }
    int grid = map->numOfItems / 1024 + 1;

    partialMinerInitialize<<<grid,1024>>>(map, minSup);
    return;
    // partialMinerInitialize(map, minSup, depth);
}

__global__ void partialMinerInitialize(dMap *map, int minSup)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    if (tid < map->numOfItems)
    // for (int tid = 0; tid < map->numOfItems; tid++)
    {
        printf("Item: %d, TID: %d\n", map->keyVal[tid]->item, tid);
        KV *keyVal = map->keyVal[tid];
        int count = 0;
        for (int i = 0; i < keyVal->itemLocationsCount; i++)
        {
            count += keyVal->itemLocations[i]->count;
        }

        if (count >= minSup)
        {
            // printf("Pattern Found\n");
            // printf("Item %d has support %d\n", keyVal->item, count);
            // patCount[tid] = count;
            // patCount++;
            // printf("Pattern Count: %d\n", patCount);
            // __syncthreads();
            // __threadfence_system();
            // atomicAdd(&patCount, 1);
            // __threadfence_system();
            // __syncthreads();
            // printf("Pattern Count: %d\n", patCount);
            partialMiner(keyVal, minSup);
        }
        return;

    }
    return;
}

__global__ void buildInitialTree(int *transactions, int *indexes, int numOfIndexes, int minSup)
{
    TreeNode *root = makeNode(-1, 0, NULL);
    dMap *top = makeMap();
    patCount = 0;

    // printf("Constructing tree\n");

    for (int i = 0; i < numOfIndexes; i++)
    {
        TreeNode *current = root;
        // printf("Num of root children: %d\n", root->childrenCount);

        for (int j = indexes[i]; j < indexes[i + 1]; j++)
        {
            int item = transactions[j];
            // printf("%d ", item);
            int count = 1;
            int location = -1;
            addChild(current, item, count, location, top);
            current = current->children[location];
        }
        
    }

    // printf("Finished constructing tree\n");
    int grid = top->numOfItems / 1024 + 1;

    // print all items in map
    partialMinerInitialize<<<grid,1024>>>(top, minSup);
    // cudaDeviceSynchronize();

    // partialMinerInitialize(top, minSup, 0);
    // printf("Num of patterns: %d\n", patCount);

    // printf("Finished mining\n");
    return;
}

__global__ void printFinalPatterns()
{
    printf("Num of patterns: %d\n", patCount);
}

void initialTree(std::string fileName, int minimumSupport)
{
    std::map<int, int> map;
    std::ifstream file(fileName);
    std::string line;

    std::vector<std::vector<int>> transactions;
    while (std::getline(file, line))
    {
        std::stringstream ss(line);
        int item;
        std::vector<int> transaction;
        while (ss >> item)
        {
            transaction.push_back(item);
            map[item]++;
        }

        transactions.push_back(transaction);
    }

    std::vector<std::pair<int, int>> vec;
    for (auto it = map.begin(); it != map.end(); it++)
    {
        vec.push_back(*it);
    }

    std::sort(vec.begin(), vec.end(), [](const std::pair<int, int> &a, const std::pair<int, int> &b)
              { return a.second > b.second; });

    for (int i = 0; i < vec.size(); i++)
    {
        if (vec[i].second < minimumSupport)
        {
            vec.erase(vec.begin() + i);
            i--;
        }
    }

    std::vector<int> keys;
    for (auto it = vec.begin(); it != vec.end(); it++)
    {
        keys.push_back(it->first);
    }

    int *indexes = new int[transactions.size() + 1];
    indexes[0] = 0;
    int sumOfTransactions = 0;
    for (int i = 0; i < transactions.size(); i++)
    {
        sumOfTransactions += transactions[i].size();

        for (int j = 0; j < transactions[i].size(); j++)
        {
            if (std::find(keys.begin(), keys.end(), transactions[i][j]) == keys.end())
            {
                transactions[i].erase(transactions[i].begin() + j);
                j--;
            }
        }

        // sort transaction using keys
        std::sort(transactions[i].begin(), transactions[i].end(), [&keys](int a, int b)
                  { return std::find(keys.begin(), keys.end(), a) < std::find(keys.begin(), keys.end(), b); });
        indexes[i + 1] = indexes[i] + transactions[i].size();
    }

    int *flattenedTransactions = new int[sumOfTransactions];
    int index = 0;
    for (int i = 0; i < transactions.size(); i++)
    {
        for (int j = 0; j < transactions[i].size(); j++)
        {
            flattenedTransactions[index] = 0;
            flattenedTransactions[index] = transactions[i][j];
            index++;
        }
    }

    int *devFlattenedTransactions;
    int *devIndexes;

    // set heap size to 1GB
    cudaDeviceSetLimit(cudaLimitMallocHeapSize, 1024*1024*1024);

    cudaMalloc((void **)&devFlattenedTransactions, sizeof(int) * sumOfTransactions);
    cudaMalloc((void **)&devIndexes, sizeof(int) * (transactions.size() + 1));

    cudaMemcpy(devFlattenedTransactions, flattenedTransactions, sizeof(int) * sumOfTransactions, cudaMemcpyHostToDevice);
    cudaMemcpy(devIndexes, indexes, sizeof(int) * (transactions.size() + 1), cudaMemcpyHostToDevice);

    buildInitialTree<<<1, 1>>>(devFlattenedTransactions, devIndexes, transactions.size(), minimumSupport);
    // buildInitialTree(flattenedTransactions, indexes, transactions.size(), minimumSupport);
    cudaDeviceSynchronize();
    printFinalPatterns<<<1, 1>>>();
    cudaDeviceSynchronize();
    // cudaFree(devFlattenedTransactions);
    // cudaFree(devIndexes);
}

int main(int argc, char *argv[])
{
    if (argc < 4)
    {
        printf("Usage: %s {file} {minimumSupport} {outputfile}\n", argv[0]);
        return 0;
    }

    // start time
    auto start = std::chrono::high_resolution_clock::now();

    std::string file = argv[1];
    int minimumSupport = atoi(argv[2]);

    initialTree(file, minimumSupport);

    auto endTime = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> diff = endTime - start;
    printf("Time(seconds): %f\n", diff.count());

    return 0;
}